# Operational runbook

## Local lifecycle

- Start: `docker compose up -d --build --wait --wait-timeout 300`.
- Inspect: `docker compose ps`, `docker compose logs --tail=100 api worker`.
- Verify: `python scripts/e2e.py`.
- Stop: `docker compose stop`; requests remain in the PostgreSQL volume.
- Start after a host restart: `docker compose up -d --wait`. LocalStack resources are recreated, and pending outbox rows can be republished. Reports from the previous local emulator lifecycle are not durable; AWS S3 reports are durable.
- `docker compose down -v` permanently removes the local database. Use it only for an intentional reset.

## Queued requests

1. Check API/worker readiness and the database connection.
2. Check unpublished outbox count and publisher logs. SNS/IAM/KMS errors retain events for retry.
3. Check SQS oldest-message age, visible/in-flight messages and worker logs.
4. Check S3 write permissions, KMS permissions and database transactions. Failed messages remain available for retry.
5. Investigate the DLQ before redrive. Preserve event IDs. Unsupported schema versions require compatible consumer deployment, not blind repeated redrive.

The worker visibility timeout is 60 seconds and processing is short. Add a visibility heartbeat before introducing longer execution tasks. The DLQ alarm has threshold zero and queue-delay alarm threshold 120 seconds for three periods. An SNS subscription must be configured for actionable notifications.

## Application rollback

Record the previous API/worker task definition ARNs before a release. If a new deployment fails, ECS circuit breaker attempts automatic rollback; the workflow compares the active task ARN to the requested ARN and fails when they differ. A failure after API promotion can leave the API updated while the worker remains older. Compatibility across one release boundary is required.

Restore previous task definitions with `aws ecs update-service --cluster CLUSTER --service SERVICE --task-definition PREVIOUS_ARN`, then `aws ecs wait services-stable`. Restore the frontend from the previous verified release with its correct runtime configuration, then invalidate HTML/configuration. Run health and user-flow checks. Update Terraform image variables to the restored digests before the next infrastructure apply.

## Credential rotation

RDS manages the administrator password in Secrets Manager. ECS injects the secret at task startup, so running tasks do not automatically refresh rotated values. Schedule rotation, force a new deployment of both ECS services immediately afterward and verify readiness. Password mismatches during this window can pause intake/processing; queued events survive. For production expansion, use separate database identities and an application rotation mechanism or RDS Proxy integration.

## Recovery

The template enables a 14-day RDS automated backup window and Multi-AZ. S3 evidence is encrypted and versioned. Multi-AZ protects against instance/AZ failures; it does not replace logical corruption recovery or regional disaster recovery.

For point-in-time recovery, restore RDS to a new identifier, reconcile the operation/audit/outbox tables, update connection configuration and redeploy. Existing processed-event IDs must be preserved. Verify S3 evidence consistency before queue redrive. Regional recovery requires rebuilding Terraform in the secondary region, restoring or replicating RDS and S3, updating Cognito/redirects and changing DNS. Measure RPO/RTO in a drill; no recovery objective is asserted without evidence.

## Security incidents

Restrict Cognito users/client scopes, revoke affected identities, preserve CloudTrail/S3 evidence and inspect WAF/CloudWatch logs. Rotate credentials and deployment trust as needed. Application audit is not tamper-proof against database administrators. Use separate audit roles and Object Lock when the retention requirement calls for it.
