# Minimal example: wire the cluster module directly (no
# workspace / multi-cluster plumbing). Useful for testing a single cluster.

terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

module "cluster" {
  source = "../../01-modules/cluster"

  cluster_name = "dev01"
  environment  = "dev"
  owner        = "platform-team"

  instance_type = "t3.medium"
  node_count    = 3
}

output "cluster_name" {
  value = module.cluster.cluster_name
}

output "kubeconfig_command" {
  value = module.cluster.kubeconfig_command
}
