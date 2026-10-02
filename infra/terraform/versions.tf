terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.7" }
  }
  # Configure an encrypted S3 backend using -backend-config before deployment.
  backend "s3" {
  }
}
provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = var.name, Environment = var.environment, ManagedBy = "Terraform" }
  }
}
data "aws_caller_identity" "current" {
}
data "aws_availability_zones" "available" {
  state = "available"
}
locals {
  prefix  = "${var.name}-${var.environment}"
  account = data.aws_caller_identity.current.account_id
  azs     = slice(data.aws_availability_zones.available.names, 0, 2)
}
