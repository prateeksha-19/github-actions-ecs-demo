# ECR repository ECS pulls from. The pipeline also pushes the same image to GHCR
# (GitHub Packages); ECR is the ECS-native, credential-free pull path.

resource "aws_ecr_repository" "this" {
  name                 = "${local.name}-server"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # Demo convenience: allows `terraform destroy` even with images present.
  force_delete = true

  tags = { Name = "${local.name}-server" }
}

# Keep the repo tidy: expire old images, retain the most recent tagged ones.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last 20 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-", "v", "latest"]
          countType     = "imageCountMoreThan"
          countNumber   = 20
        }
        action = { type = "expire" }
      },
    ]
  })
}
