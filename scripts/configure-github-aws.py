"""Configure the production GitHub environment from verified Terraform outputs."""
import argparse
import json
import subprocess
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('outputs', type=Path)
p.add_argument('--account-id', required=True)
p.add_argument('--region', required=True)
p.add_argument('--repo', default='jorgefprietol/atlas-cloud-operations')
args = p.parse_args()
outputs = json.loads(args.outputs.read_text(encoding='utf-8-sig'))
value = lambda key: outputs[key]['value']
values = {
    'AWS_ACCOUNT_ID': args.account_id, 'AWS_REGION': args.region,
    'AWS_DEPLOY_ROLE_ARN': value('deploy_role_arn'), 'ECS_CLUSTER': value('cluster_name'),
    'API_SERVICE': value('services')['api'], 'WORKER_SERVICE': value('services')['worker'],
    'API_TASK_FAMILY': value('task_families')['api'], 'WORKER_TASK_FAMILY': value('task_families')['worker'],
    'API_ECR': value('ecr_repositories')['api'], 'WORKER_ECR': value('ecr_repositories')['worker'],
    'FRONTEND_BUCKET': value('frontend_bucket'), 'CLOUDFRONT_ID': value('cloudfront_distribution_id'),
    'FRONTEND_CONFIG': json.dumps(value('frontend_config'), separators=(',', ':')), 'FRONTEND_URL': value('frontend_url')
}
subprocess.run(['gh','api','--method','PUT',f'repos/{args.repo}/environments/production'], check=True, stdout=subprocess.DEVNULL)
for name, text in values.items():
    subprocess.run(['gh','variable','set',name,'--repo',args.repo,'--env','production'], input=text, text=True, check=True)
print('Configured production environment variables; review environment deployment rules in GitHub.')
