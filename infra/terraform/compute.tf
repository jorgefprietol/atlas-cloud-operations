locals {
  services = {
    api    = { image = var.api_image, port = 8080, cpu = 256, memory = 512 }
    worker = { image = var.worker_image, port = 8081, cpu = 512, memory = 1024 }
  }
  task_trust = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole", Condition = { StringEquals = { "aws:SourceAccount" = local.account } } }] })
  db_secret  = aws_db_instance.main.master_user_secret[0].secret_arn
}
resource "aws_ecr_repository" "services" {
  for_each             = local.services
  name                 = "${local.prefix}-${each.key}"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}
resource "aws_ecs_cluster" "main" {
  name = local.prefix
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}
resource "aws_cloudwatch_log_group" "services" {
  for_each          = local.services
  name              = "/ecs/${local.prefix}/${each.key}"
  retention_in_days = 30
}
resource "aws_iam_role" "execution" {
  name               = "${local.prefix}-execution"
  assume_role_policy = local.task_trust
}
resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy" "execution_secrets" {
  role   = aws_iam_role.execution.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = local.db_secret }] })
}
resource "aws_iam_role" "task" {
  for_each           = local.services
  name               = "${local.prefix}-${each.key}-task"
  assume_role_policy = local.task_trust
}
resource "aws_iam_role_policy" "api" {
  role = aws_iam_role.task["api"].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["sns:Publish"], Resource = aws_sns_topic.operations.arn },
    { Effect = "Allow", Action = ["kms:Decrypt", "kms:GenerateDataKey"], Resource = aws_kms_key.main.arn }
  ] })
}
resource "aws_iam_role_policy" "worker" {
  role = aws_iam_role.task["worker"].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = aws_sqs_queue.operations.arn },
    { Effect = "Allow", Action = ["s3:PutObject"], Resource = "${aws_s3_bucket.reports.arn}/reports/*" },
    { Effect = "Allow", Action = ["kms:Decrypt", "kms:GenerateDataKey"], Resource = aws_kms_key.main.arn }
  ] })
}
resource "aws_ecs_task_definition" "services" {
  for_each                 = local.services
  family                   = "${local.prefix}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task[each.key].arn
  container_definitions = jsonencode([{
    name                   = each.key, image = each.value.image, essential = true,
    portMappings           = [{ containerPort = each.value.port, protocol = "tcp" }],
    readonlyRootFilesystem = true,
    environment = concat([
      { name = "AWS_REGION", value = var.region },
      { name = "DB_USER", value = "atlasadmin" }
      ], each.key == "api" ? [
      { name = "ASPNETCORE_ENVIRONMENT", value = "Production" },
      { name = "DB_HOST", value = aws_db_instance.main.address },
      { name = "SNS_TOPIC_ARN", value = aws_sns_topic.operations.arn },
      { name = "OIDC_ISSUER", value = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}" },
      { name = "OIDC_CLIENT_ID", value = aws_cognito_user_pool_client.web.id }
      ] : [
      { name = "JDBC_URL", value = "jdbc:postgresql://${aws_db_instance.main.address}:5432/atlas?sslmode=verify-full&sslrootcert=/app/rds-ca.pem" },
      { name = "SQS_QUEUE_URL", value = aws_sqs_queue.operations.url },
      { name = "REPORT_BUCKET", value = aws_s3_bucket.reports.id },
      { name = "JAVA_TOOL_OPTIONS", value = "-Djava.io.tmpdir=/tmp" }
    ]),
    secrets          = [{ name = "DB_PASSWORD", valueFrom = "${local.db_secret}:password::" }],
    logConfiguration = { logDriver = "awslogs", options = { "awslogs-group" = aws_cloudwatch_log_group.services[each.key].name, "awslogs-region" = var.region, "awslogs-stream-prefix" = each.key } },
    mountPoints      = [{ sourceVolume = "scratch", containerPath = "/tmp", readOnly = false }],
    healthCheck = {
      command  = ["CMD-SHELL", "bash -c 'exec 3<>/dev/tcp/127.0.0.1/${each.value.port}; printf \"GET ${each.key == "api" ? "/health/ready" : "/actuator/health/readiness"} HTTP/1.0\\r\\nHost: localhost\\r\\n\\r\\n\" >&3; cat <&3 | head -1 | grep -q 200'"],
      interval = 30, timeout = 5, retries = 3, startPeriod = 60
    }
  }])
  volume {
    name = "scratch"
  }
  depends_on = [aws_iam_role_policy.execution_secrets, aws_iam_role_policy_attachment.execution]
}
resource "aws_ecs_service" "services" {
  for_each                           = local.services
  name                               = "${local.prefix}-${each.key}"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.services[each.key].arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "1.4.0"
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }
  dynamic "load_balancer" {
    for_each = each.key == "api" ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.api.arn
      container_name   = "api"
      container_port   = 8080
    }
  }
  depends_on = [aws_lb_listener.https, aws_nat_gateway.main, aws_iam_role_policy.api, aws_iam_role_policy.worker]
}
resource "aws_appautoscaling_target" "services" {
  for_each           = local.services
  min_capacity       = var.desired_count
  max_capacity       = 6
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.services[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}
resource "aws_appautoscaling_policy" "cpu" {
  for_each           = local.services
  name               = "${local.prefix}-${each.key}-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.services[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.services[each.key].scalable_dimension
  service_namespace  = "ecs"
  target_tracking_scaling_policy_configuration {
    target_value = 60
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    scale_in_cooldown  = 120
    scale_out_cooldown = 60
  }
}
