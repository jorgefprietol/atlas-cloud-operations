# Cloud capability map

The runtime implements a coherent operational governance flow. Infrastructure is ready for later AWS configuration. The table separates executable components from alternatives and organization-level integrations; creating redundant managed services would add cost without improving this bounded product.

| Capability | Implementation in this repository | Extension / alternative |
| --- | --- | --- |
| IAM, STS and federation | Separate ECS roles; temporary GitHub OIDC credentials; Cognito access tokens and PKCE | Enterprise SAML/OIDC federation and per-group authorization |
| IAM Access Analyzer | Scoped trust and resource policies declared in Terraform | Organization analyzer and policy validation in central security account |
| Organizations, SCPs, Identity Center, Control Tower, RAM, Directory Service | Application resides in an isolated workload VPC/account boundary | Landing zone, account vending, deny guardrails, shared services and workforce identity belong to management-account infrastructure |
| CloudTrail, KMS, Secrets Manager | Multi-region management trail plus report S3 data events; rotating KMS key; RDS-managed secret | Central log archive, cross-account keys and automated app credential refresh |
| Parameter Store | Runtime nonsecret configuration uses ECS environment variables and static frontend JSON | Shared configuration hierarchy in SSM when multiple environments need it |
| TLS, ACM, RDS and S3 security | ACM-backed HTTPS listener; validated RDS TLS; private encrypted DB; S3 public-access blocks and TLS-only policies | Private PKI, CloudHSM and stricter key segregation for regulated environments |
| S3 access points, multi-region access, Object Lambda | Application role writes only `reports/*`; no public report endpoint | Access points and cross-region replication at larger data-sharing scale; transformations via dedicated service |
| Shield, WAF and Firewall Manager | CloudFront/ALB edge, managed WAF rules and rate limit | Shield Advanced and centralized Firewall Manager for account fleets |
| GuardDuty, Inspector, Security Hub, Detective, Config | Optional GuardDuty detector; CI image vulnerability scans; ECR scan on push; CloudTrail | Existing organization delegated administrators should own central posture/detection, Inspector, Config recorder and remediation aggregation |
| EC2, ASG, launch strategies, Spot | Managed container workload on Fargate; CPU autoscaling; ECS circuit breaker and rolling update | EC2/Spot capacity providers for predictable batch or interruptible capacity; Outposts/Local Zones/Wavelength only with a real locality requirement |
| ECS, ECR, EKS, Anywhere | Fargate services and immutable ECR repositories; independent API/worker images | EKS for Kubernetes-specific operational requirements; Anywhere for on-prem execution |
| Lambda, API Gateway and AppSync | HTTP workload on ASP.NET Core behind ALB and CloudFront | Lambda/API Gateway for bursty small functions; AppSync for GraphQL/subscriptions |
| Route 53, hybrid DNS, Global Accelerator | Route 53 alias for the HTTPS origin | Health-based regional failover, resolver endpoints and acceleration after recovery requirements are established |
| EBS, instance store, EFS, FSx | Managed RDS storage; stateless tasks; durable report objects in S3 | Shared filesystem or Windows/HPC storage only for workloads needing file semantics |
| DataSync, Transfer Family, Data Exchange | JSON evidence generated directly into S3 | Managed migration, partner SFTP and third-party dataset ingestion as independent workflows |
| S3 lifecycle and cost controls | Versioning, 90-day Glacier Instant Retrieval transition, private buckets | Storage Lens, inventory, access-cost attribution and policy-based legal retention |
| CloudFront and edge functions | Private S3 frontend via OAC; SPA routing function; cache separation for assets/API | Lambda@Edge for more complex edge transformations |
| ElastiCache and extreme request rates | SQL indexes and bounded request-list response; API cache disabled to preserve ownership | Redis for expensive shared calculations; retain idempotency in durable storage |
| RDS, Aurora, DynamoDB, OpenSearch | PostgreSQL transactional model, Multi-AZ and automated backups | Aurora for capacity/failover needs; DynamoDB for key-value access; OpenSearch for broad indexed discovery |
| SNS, SQS, retries and fan-out | SNS-to-SQS subscription, raw versioned events, visibility timeout, retries and DLQ | Additional subscriptions isolate notification/analytics consumers; Amazon MQ only for required broker protocols |
| Step Functions | Java evaluates a short deterministic policy transaction | Human approval/long-running external execution can become a state machine with compensations |
| Kinesis, Firehose, Flink and MSK | Queue-based commands fit low-volume operational intake | Streaming and event-time analytics after measured throughput and ordering requirements exist |
| Batch and EMR | Lightweight policy tasks run continuously in Java | Batch compute or EMR for genuinely large processing jobs |
| Glue and Athena | Optional Terraform catalog and SQL workgroup over report JSON | Enable `enable_analytics`; assign a separate analyst role and validate sample reports in AWS |
| Redshift, QuickSight, DocumentDB, Timestream | Operational dataset stays in PostgreSQL/S3 | Warehouse/BI, document or time-series stores only after data shape and reporting justify them |
| Resilience and cost | Two AZs, queue buffering, backups, deterministic retry, deployment rollback | Cross-region recovery drill, budget alarms, capacity/load tests and measured RPO/RTO |

This map is architecture documentation. Only the column labeled implementation and explicitly included optional Terraform components are delivered code. Organization integrations and alternative products are design choices awaiting their corresponding requirements and configuration.
