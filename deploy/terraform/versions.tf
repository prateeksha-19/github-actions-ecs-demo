terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # For anything beyond a single-operator demo, store state remotely so it is
  # shared and locked. Create the bucket + DynamoDB table first, then uncomment.
  #
  # backend "s3" {
  #   bucket         = "your-tf-state-bucket"
  #   key            = "transcriptionsuite/ecs/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "your-tf-lock-table"
  #   encrypt        = true
  # }
}
