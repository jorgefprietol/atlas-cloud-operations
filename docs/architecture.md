# Architecture decisions

## System boundaries

The system validates operational requests; it does not provision infrastructure on a user's behalf. `backup`, `data-export` and `service-release` identify policy evaluation scenarios. The Java worker creates a real JSON evaluation report in S3. An external execution adapter is an explicit future extension; it must respect independent approvals and least-privilege service roles.

C# owns the HTTP interface and request intake. Java owns asynchronous evaluation. React presents the operational state. NestJS would add an unnecessary third backend runtime; React suits the focused console and OAuth2 redirect flow. Both backend services participate in a single bounded context and share a PostgreSQL schema. This deliberately trades database independence for strong consistency and straightforward deduplication.

## Consistency and delivery

1. The API validates fields and requires an idempotency key. Its SHA-256 payload hash detects reuse with different content.
2. A unique constraint on `(actor, idempotency_key)` serializes competing inserts. One request gets HTTP 201; replays get HTTP 200 with the same operation identity. A conflicting payload gets HTTP 409.
3. The operation, initial audit entry and outbox event commit together.
4. The publisher locks one pending row with `FOR UPDATE SKIP LOCKED`, publishes to SNS and marks it published in the same database transaction. A crash after SNS accepts the event can create a duplicate delivery.
5. SQS provides at-least-once delivery. Java inserts the event UUID into `processed_events` in the same transaction as the final operation status and audit entry. Competing consumers block on the UUID constraint; only one records the result.
6. The worker stores an S3 report before committing SQL. A failed transaction may leave an S3 object; a retry overwrites the same key with the same deterministic report content. This is idempotent recovery, not a distributed atomic transaction. Versioned S3 may retain multiple identical versions.
7. Java acknowledges SQS only after successful transaction completion. Unexpected schemas and processing failures are retried, then moved to the DLQ after three receives.

Lock scope includes the S3 call. The current policy evaluation is short and messages use a 60-second visibility timeout. Before introducing slow adapters, add visibility heartbeat, timeouts and a second transactional stage. Keep event IDs and schema version backward compatible during rolling deployments.

## Authentication and ownership

Local mode is explicitly ASP.NET `Development` and requires a generated token. AWS sets `Production`, requires the OIDC issuer and client ID, validates signatures, issuer and expiration, and checks Cognito access-token type, client ID and `atlas/operate` scope. ID tokens cannot authorize API access. Records are scoped to the immutable JWT subject, including detail and audit queries. Unknown or foreign IDs return 404 or an empty audit collection.

The SPA uses authorization code plus PKCE, without a client secret. The access token expires after 15 minutes; the application clears the operational view on token expiration. Users are created by an administrator; self-registration is disabled. Identity federation through Cognito is an extension requiring provider configuration.

## Infrastructure

Two availability zones host private Fargate tasks and an encrypted Multi-AZ RDS database. Each zone has a NAT gateway. S3 has a gateway endpoint. Public ALB HTTPS is protected by WAF and a CloudFront origin header. CloudFront serves a private S3 frontend through Origin Access Control and forwards API authorization with caching disabled. RDS connections validate TLS certificates against the official bundled CA.

Separate task IAM roles grant SNS publishing to the API and SQS consumption/S3 report writes to the worker. The ECS execution role reads the RDS-managed password from Secrets Manager. The deployment role trusts only the named repository's `production` GitHub environment and can promote images, update ECS task definitions and publish frontend artifacts.

## Operational limits

- Terraform has been designed for later deployment; local emulation cannot validate actual IAM, billing, regional quotas, Cognito login or cloud service integration.
- Both services currently use the RDS managed administrator identity. Before handling production-sensitive data, provision separate database users/roles and versioned migrations. Startup DDL is serialized through a PostgreSQL advisory lock; `CREATE TABLE IF NOT EXISTS` is a bootstrap mechanism, not a schema migration framework.
- The managed RDS password can rotate while task environment variables retain the old value. Coordinate rotation with new ECS deployments; see the runbook.
- Audit entries are append-only through application code. Database administrators can edit them. S3 versioning and CloudTrail provide evidence; legal retention would require Object Lock, explicit retention policy and restricted audit administration.
- Requested retention is evaluated as a policy input. It does not configure the retention of underlying customer data. Report objects transition to Glacier Instant Retrieval after 90 days; they have no automatic current-version deletion rule.
- No measured production SLA or multi-region failover is claimed. Backup/restore, regional rebuild and Route 53 failover require an exercised recovery plan.
- The console shows the latest 100 requests of the current identity; summary cards use exactly that dataset. Add cursor pagination before larger usage.
- Logout clears this application's session; Cognito's provider session can remain active. Configure global sign-out for environments requiring provider logout.
- CPU-based autoscaling is included. Worker scaling by queue backlog per task is a later improvement.
- Container base tags are tracked through Dependabot/manual refresh rather than pinned to digests. Published release images are deployed by immutable digest.
