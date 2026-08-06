resource "aws_ecs_cluster" "this" {
  name = "${local.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${local.name}-cluster" }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name}"
  retention_in_days = var.log_retention_days

  tags = { Name = "${local.name}-logs" }
}

locals {
  container_name = "${local.name}-server"

  # The seed image. Terraform only needs *an* image reference so the service can
  # be created; the pipeline registers new revisions pointing at real ECR tags
  # and the service ignores changes to task_definition after creation. Before the
  # first pipeline run this tag will not exist yet, so tasks retry until it does.
  seed_image = "${aws_ecr_repository.this.repository_url}:latest"

  # CPU-mode runtime configuration. PYTORCH_VARIANT=cpu makes first-boot bootstrap
  # install CPU-only PyTorch wheels instead of multi-GB CUDA wheels.
  container_environment = [
    { name = "PYTORCH_VARIANT", value = "cpu" },
    { name = "SERVER_HOST", value = "0.0.0.0" },
    { name = "SERVER_PORT", value = tostring(var.container_port) },
    { name = "DATA_DIR", value = "/data" },
    { name = "LOG_LEVEL", value = "INFO" },
    { name = "TLS_ENABLED", value = "false" },
    { name = "BOOTSTRAP_REQUIRE_HF_TOKEN", value = "false" },
    { name = "INSTALL_WHISPER", value = "false" },
    { name = "INSTALL_NEMO", value = "false" },
    { name = "INSTALL_FUNASR", value = "false" },
    { name = "INSTALL_VIBEVOICE_ASR", value = "false" },
  ]

  # Only mount /data when EFS is enabled.
  container_mount_points = var.enable_efs ? [
    { sourceVolume = "data", containerPath = "/data", readOnly = false }
  ] : []

  container_definitions = [
    {
      name        = local.container_name
      image       = local.seed_image
      essential   = true
      environment = local.container_environment
      mountPoints = local.container_mount_points

      portMappings = [
        { containerPort = var.container_port, protocol = "tcp" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "app"
        }
      }

      # Container-level health check mirrors the image's own HEALTHCHECK. Long
      # start period: first boot bootstraps CPU PyTorch wheels before /health serves.
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}/health || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 900
      }
    }
  ]
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${local.name}-server"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  ephemeral_storage {
    size_in_gib = var.ephemeral_storage_gib
  }

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode(local.container_definitions)

  dynamic "volume" {
    for_each = var.enable_efs ? [1] : []
    content {
      name = "data"
      efs_volume_configuration {
        file_system_id     = aws_efs_file_system.data[0].id
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = aws_efs_access_point.data[0].id
          iam             = "DISABLED"
        }
      }
    }
  }

  # The pipeline owns the live task definition (image tag changes every deploy).
  # Terraform only seeds the first revision, so ignore drift on the moving parts.
  lifecycle {
    ignore_changes = [container_definitions]
  }
}

resource "aws_ecs_service" "this" {
  name            = "${local.name}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = true # required for ECR pulls without a NAT gateway
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = local.container_name
    container_port   = var.container_port
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # After creation the pipeline drives task_definition (new image each deploy) and
  # operators/autoscaling may change desired_count — don't let Terraform revert them.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.http]
}
