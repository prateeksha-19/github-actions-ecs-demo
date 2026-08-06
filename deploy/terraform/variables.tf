variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to prefix/tag all created resources."
  type        = string
  default     = "transcriptionsuite"
}

variable "github_repo" {
  description = "GitHub repository in owner/name form. Used to scope the OIDC trust policy so only this repo's workflows can assume the deploy role."
  type        = string
  default     = "prateeksha-19/github-actions-demo"
}

variable "github_oidc_subjects" {
  description = <<-EOT
    List of GitHub OIDC `sub` claim patterns allowed to assume the deploy role.
    Defaults to pushes on main and any tag. Broaden to "repo:<repo>:*" to allow
    every branch/PR (less safe). See:
    https://docs.github.com/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
  EOT
  type        = list(string)
  default = [
    "repo:prateeksha-19/github-actions-demo:ref:refs/heads/main",
    "repo:prateeksha-19/github-actions-demo:ref:refs/tags/*",
  ]
}

variable "create_oidc_provider" {
  description = "Create the GitHub Actions OIDC provider. Set to false if the account already has one (an account may only have a single provider per URL)."
  type        = bool
  default     = true
}

variable "container_port" {
  description = "Port the TranscriptionSuite server listens on inside the container."
  type        = number
  default     = 9786
}

variable "desired_count" {
  description = "Number of Fargate tasks to run. NOTE: the service ignores changes to this after creation so the pipeline/console can scale freely."
  type        = number
  default     = 1
}

variable "task_cpu" {
  description = "Fargate task CPU units (1024 = 1 vCPU). CPU-mode transcription is compute-heavy; 2048 is a reasonable demo floor."
  type        = string
  default     = "2048"
}

variable "task_memory" {
  description = "Fargate task memory (MiB). Must be a valid pairing with task_cpu. CPU PyTorch + models are memory-hungry."
  type        = string
  default     = "8192"
}

variable "ephemeral_storage_gib" {
  description = "Fargate ephemeral storage (GiB, 21-200). First-boot dependency bootstrap (uv sync of CPU torch/whisper) plus model cache need well above the 20 GiB default."
  type        = number
  default     = 50
}

variable "enable_efs" {
  description = "Mount an EFS access point at /data so transcription results survive task restarts/redeploys (honors the project's data-loss invariant). /models and /runtime remain ephemeral."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the ECS task log group."
  type        = number
  default     = 14
}

variable "health_check_grace_period_seconds" {
  description = "Grace period before the ALB starts failing unhealthy tasks. Generous because first boot bootstraps CPU PyTorch wheels, which can take several minutes."
  type        = number
  default     = 900
}
