# Security

Report vulnerabilities privately through the repository owner's GitHub contact before opening a public issue with sensitive details. Do not include credentials, user data or Terraform state in issue reports.

The API rejects unauthenticated access. Production validates Cognito access tokens, their issuer/signature/expiry, token type, application client and operational scope. Request, list and audit queries isolate records by the token subject. Local development uses a randomly generated token and only publishes the frontend on loopback.

SQL uses parameters. Secrets are excluded from version control. AWS workloads use ECS task roles and Secrets Manager; GitHub Actions assumes a repository/environment-scoped OIDC role. Cognito uses PKCE, no browser client secret, invited users and optional software-token MFA. Enforce MFA according to the target organization's requirements.

S3 public access is blocked, report encryption uses a rotating KMS key, and RDS is private with certificate-validated TLS. CloudFront security headers restrict scripts to the application origin. WAF handles common rules and forwarded-client rate limits on the ALB. TLS is terminated at ALB and internal traffic travels inside private subnets.

The CI pipeline scans committed secrets and blocks published application images on fixable high/critical vulnerabilities. Trivy's `ignore-unfixed` means unfixed vendor advisories remain a residual risk; a passing scan does not guarantee an absence of vulnerabilities. NuGet/npm lockfiles and pinned workflow commits support reproducibility. Dependency updates require rerunning the same pipeline.

Before production-sensitive use, separate database roles, adopt versioned migrations, coordinate managed-password rotation, configure alert destinations, enforce the appropriate MFA policy and run a recovery exercise. See the architecture and runbook for the precise scope of these controls.
