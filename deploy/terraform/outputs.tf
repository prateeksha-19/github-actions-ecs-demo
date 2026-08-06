# These outputs map 1:1 to the GitHub Actions repository variables you set after
# `terraform apply`. See deploy/README.md.

output "aws_region" {
  description = "-> GitHub repo variable AWS_REGION"
  value       = var.aws_region
}

output "github_actions_role_arn" {
  description = "-> GitHub repo variable AWS_DEPLOY_ROLE_ARN (role the workflow assumes via OIDC)"
  value       = aws_iam_role.github_actions_deploy.arn
}

output "ecr_repository_name" {
  description = "-> GitHub repo variable ECR_REPOSITORY"
  value       = aws_ecr_repository.this.name
}

output "ecr_repository_url" {
  description = "Full ECR image repository URL"
  value       = aws_ecr_repository.this.repository_url
}

output "ecs_cluster_name" {
  description = "-> GitHub repo variable ECS_CLUSTER"
  value       = aws_ecs_cluster.this.name
}

output "ecs_service_name" {
  description = "-> GitHub repo variable ECS_SERVICE"
  value       = aws_ecs_service.this.name
}

output "ecs_task_family" {
  description = "-> GitHub repo variable ECS_TASK_FAMILY"
  value       = aws_ecs_task_definition.this.family
}

output "container_name" {
  description = "-> GitHub repo variable CONTAINER_NAME"
  value       = local.container_name
}

output "alb_url" {
  description = "Public URL of the service once tasks are healthy"
  value       = "http://${aws_lb.this.dns_name}"
}

output "health_url" {
  description = "Health endpoint used by the ALB target group"
  value       = "http://${aws_lb.this.dns_name}/health"
}
