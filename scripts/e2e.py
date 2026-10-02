"""Exercise real C# -> PostgreSQL -> SNS/SQS -> Java -> S3 behavior."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import json
import os
import subprocess
import time
import urllib.request
import urllib.error
import uuid

root = Path(__file__).resolve().parents[1]
env = dict(line.split('=', 1) for line in (root / '.env').read_text().splitlines() if '=' in line)
base = os.environ.get('ATLAS_URL', 'http://127.0.0.1:18096')

def request(path, body=None, key=None, token=None):
    headers = {'Authorization': 'Bearer ' + (token if token is not None else env['DEV_API_TOKEN'])}
    if key: headers['Idempotency-Key'] = key
    if body is not None: headers['Content-Type'] = 'application/json'
    r = urllib.request.Request(base + path, data=json.dumps(body).encode() if body is not None else None, headers=headers)
    try:
        with urllib.request.urlopen(r, timeout=15) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as e:
        text = e.read()
        return e.code, json.loads(text) if text else None

def cli(service, *args):
    return subprocess.check_output(['docker', 'compose', 'exec', '-T', service, *args], cwd=root, text=True).strip()

def wait_complete(id):
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        code, item = request('/api/requests/' + id)
        assert code == 200
        if item['status'] != 'queued': return item
        time.sleep(1)
    raise AssertionError('Worker did not finish within 90 seconds')

assert request('/api/requests', token='invalid')[0] == 401
payload = {'title': 'Monthly audit backup', 'kind': 'backup', 'region': 'us-east-1', 'classification': 'confidential', 'retentionDays': 365}
assert request('/api/requests', payload)[0] == 400
invalid = dict(payload, retentionDays=0)
assert request('/api/requests', invalid, str(uuid.uuid4()))[0] == 400
key = str(uuid.uuid4())
with ThreadPoolExecutor(max_workers=6) as pool:
    results = list(pool.map(lambda _: request('/api/requests', payload, key), range(6)))
assert sorted(x[0] for x in results) == [200, 200, 200, 200, 200, 201]
assert len({x[1]['id'] for x in results}) == 1
operation_id = results[0][1]['id']
assert request('/api/requests', dict(payload, title='Different payload'), key)[0] == 409
assert request('/api/requests/' + str(uuid.uuid4()))[0] == 404
finished = wait_complete(operation_id)
assert finished['status'] == 'validated'
audit = request('/api/requests/' + operation_id + '/audit')[1]
assert [x['action'] for x in audit] == ['requested', 'validated']
report = json.loads(cli('localstack', 'awslocal', 's3', 'cp', 's3://atlas-reports-local/' + finished['reportKey'], '-'))
assert report['operationId'] == operation_id and report['status'] == 'validated'
event = cli('postgres', 'psql', '-U', 'atlas', '-d', 'atlas', '-Atc', f"SELECT payload::text FROM outbox WHERE payload->>'operationId'='{operation_id}'")
cli('localstack', 'awslocal', 'sqs', 'send-message', '--queue-url', 'http://localhost:4566/queue/us-east-1/000000000000/atlas-operations', '--message-body', event)
time.sleep(12)
assert len(request('/api/requests/' + operation_id + '/audit')[1]) == 2, 'Duplicate delivery created an extra audit event'
foreign_id = str(uuid.uuid4())
cli('postgres', 'psql', '-U', 'atlas', '-d', 'atlas', '-c', f"INSERT INTO operations(id,actor,idempotency_key,payload_hash,title,kind,region,classification,retention_days) VALUES('{foreign_id}','different-operator','foreign-key','hash','Isolated record','backup','us-east-1','internal',90)")
assert request('/api/requests/' + foreign_id)[0] == 404
assert request('/api/requests/' + foreign_id + '/audit')[1] == []
code, rejected = request('/api/requests', dict(payload, title='Restricted export', kind='data-export'), str(uuid.uuid4()))
assert code == 201 and wait_complete(rejected['id'])['status'] == 'rejected'
print('PASS: authentication, validation, concurrent idempotency, conflict handling, account isolation, asynchronous decisions, audit, S3 evidence, duplicate delivery.')
