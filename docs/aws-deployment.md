# AWS deployment

The repository can be configured for AWS later. Local and CI tests do not require an AWS account. No AWS resources have been deployed as part of repository creation.

## Prerequisites

- AWS account, AWS CLI authenticated through a human/admin role, Terraform 1.14.7, Docker, Node.js 22 and GitHub CLI.
- Route 53 hosted zone and a validated ACM certificate in the target region for `api-atlas.your-domain`.
- Existing IAM OIDC provider `token.actions.githubusercontent.com` with audience `sts.amazonaws.com`. Reuse an organization-managed provider.
- Encrypted, versioned S3 bucket for Terraform state, access restricted to infrastructure administrators. Terraform state includes sensitive origin-header material; never publish it.
- Budget and quota review: the template uses two NAT gateways, RDS Multi-AZ, ALB, Fargate tasks, WAF, CloudFront, storage and logs. These resources incur charges even without traffic. Downsize intentionally for a nonproduction account.

References: [ECS execution roles](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html), [GitHub OIDC in AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws), [RDS TLS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html).

## First deployment

1. Copy `infra/terraform/terraform.tfvars.example` to the ignored `terraform.tfvars`. Configure account, region, hosted zone, API hostname, ACM certificate and OIDC provider ARN.
2. Initialize state:

```powershell
terraform -chdir=infra/terraform init -backend-config="bucket=YOUR_STATE_BUCKET" -backend-config="key=atlas/production.tfstate" -backend-config="region=us-east-1" -backend-config="encrypt=true" -backend-config="use_lockfile=true"
```

3. Set syntactically valid temporary digest references in both image variables (64 zeroes are sufficient for this targeted bootstrap). Create only the two ECR repositories:

```powershell
terraform -chdir=infra/terraform plan -target=aws_ecr_repository.services -out=bootstrap.tfplan
terraform -chdir=infra/terraform apply bootstrap.tfplan
```

Targeted apply is limited to this bootstrap. Do not use placeholder digests in a full deployment.

4. Select a complete successful `Quality and Containers` run. Pull the verified GHCR images using its full commit SHA and push them to the corresponding ECR repositories. Use the actual registry/account in the following example:

```powershell
$releaseSha = 'REPLACE_WITH_VERIFIED_FULL_COMMIT_SHA'
$registry = '123456789012.dkr.ecr.us-east-1.amazonaws.com'
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $registry
docker pull "ghcr.io/jorgefprietol/atlas-cloud-operations-api:$releaseSha"
docker tag "ghcr.io/jorgefprietol/atlas-cloud-operations-api:$releaseSha" "$registry/atlas-production-api:$releaseSha"
docker push "$registry/atlas-production-api:$releaseSha"
docker pull "ghcr.io/jorgefprietol/atlas-cloud-operations-worker:$releaseSha"
docker tag "ghcr.io/jorgefprietol/atlas-cloud-operations-worker:$releaseSha" "$registry/atlas-production-worker:$releaseSha"
docker push "$registry/atlas-production-worker:$releaseSha"
aws ecr describe-images --repository-name atlas-production-api --image-ids "imageTag=$releaseSha" --query "imageDetails[0].imageDigest" --output text
aws ecr describe-images --repository-name atlas-production-worker --image-ids "imageTag=$releaseSha" --query "imageDetails[0].imageDigest" --output text
```

If GHCR requires authentication, use `gh auth token | docker login ghcr.io --username jorgefprietol --password-stdin`; never print the token. Put the resulting ECR `repository@sha256:...` references into the image variables.

5. Run a full plan and inspect it before applying:

```powershell
terraform -chdir=infra/terraform plan -out=production.tfplan
terraform -chdir=infra/terraform apply production.tfplan
terraform -chdir=infra/terraform output -json > artifacts/aws-outputs.json
```

Create the ignored `artifacts` directory before writing outputs. Preserve outputs privately. Allow several minutes for Cognito, CloudFront, ALB/DNS and RDS readiness. API bootstrap initializes the schema; Java can retry until the schema is ready.

## GitHub environment

Create/configure the `production` environment, restrict it to `main`, and set a required reviewer where your GitHub plan permits it. The IAM trust references this environment exactly. Infrastructure provisioning remains a separate administrator operation.

Run `python scripts/configure-github-aws.py artifacts/aws-outputs.json --account-id YOUR_ACCOUNT_ID --region us-east-1` to populate the repository's `production` environment variables from Terraform outputs. Review the inputs first; the helper uses the already authenticated GitHub CLI.

| GitHub variable | Terraform output or value |
| --- | --- |
| AWS_REGION / AWS_ACCOUNT_ID | Target region / account |
| AWS_DEPLOY_ROLE_ARN | deploy_role_arn |
| ECS_CLUSTER | cluster_name |
| API_SERVICE / WORKER_SERVICE | services.api / services.worker |
| API_TASK_FAMILY / WORKER_TASK_FAMILY | task_families.api / task_families.worker |
| API_ECR / WORKER_ECR | ecr_repositories.api / ecr_repositories.worker |
| FRONTEND_BUCKET | frontend_bucket |
| CLOUDFRONT_ID | cloudfront_distribution_id |
| FRONTEND_CONFIG | JSON serialization of frontend_config |
| FRONTEND_URL | frontend_url |

No static AWS key is required. Dispatch `Deploy AWS` from `main`, supplying the full commit SHA of a successful CI run on `main`. The workflow checks that evidence, promotes verified GHCR images into ECR, registers task definitions with digests, waits for ECS stability and rejects circuit-breaker rollback. It then publishes the React build and runtime Cognito configuration to S3.

## Initial access

Use the `cognito_user_pool_id` output to create an administrator-invited user in Cognito. Resolve email verification and the temporary-password change. Open `frontend_url`, select sign-in, and complete the Cognito flow. The application requests `openid atlas/operate` and uses an access token, never an ID token, for API requests. No user passwords are included in the repository.

Subscribe the appropriate operations destination to `alerts_topic_arn` separately. No notifications are sent automatically by repository setup.

## Subsequent infrastructure changes

ECS release deployment updates task definitions outside Terraform. Before a future full Terraform apply, update `api_image` and `worker_image` in the infrastructure inputs to the active production digests. Otherwise Terraform can revert a deployed application version. A release consists of separate API/worker rolling updates and frontend publication; the runbook describes partial-failure recovery.

RDS, ALB and Cognito enable deletion protection. Removing this environment is an intentional administrator operation with final snapshots and retained evidence, not a one-command cleanup.
