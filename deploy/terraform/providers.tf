provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Component = "ecs-deploy"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = var.project_name

  # First two available AZs — enough for a highly-available ALB + Fargate service.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}
