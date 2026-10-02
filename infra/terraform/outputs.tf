output "frontend_url" {
  value = "https://${aws_cloudfront_distribution.web.domain_name}"
}
output "frontend_bucket" {
  value = aws_s3_bucket.web.id
}
output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.web.id
}
output "cluster_name" {
  value = aws_ecs_cluster.main.name
}
output "services" {
  value = { for k, s in aws_ecs_service.services : k => s.name }
}
output "task_families" {
  value = { for k, t in aws_ecs_task_definition.services : k => t.family }
}
output "ecr_repositories" {
  value = { for k, r in aws_ecr_repository.services : k => r.repository_url }
}
output "deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}
output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}
output "frontend_config" {
  value = {
    mode        = "production"
    authority   = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
    clientId    = aws_cognito_user_pool_client.web.id
    redirectUri = "https://${aws_cloudfront_distribution.web.domain_name}/auth/callback"
  }
}
