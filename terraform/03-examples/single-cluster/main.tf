# Minimal example: wire the cluster module directly (no
# workspace / multi-cluster plumbing). Useful for testing a single cluster.

terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
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

  # Required - no default, to avoid CIDR collisions if you run multiple
  # clusters/examples in the same AWS account. Pick a unique range per cluster.
  vpc_cidr = "10.0.0.0/16"
  pod_cidr = "100.64.0.0/16"

  # Add any other IAM users/roles (e.g. your console role) that need
  # cluster-admin access besides whoever runs `terraform apply`.
  additional_admin_principal_arns = []
}

# Kubernetes/Helm providers authenticate against the cluster created by this
# same apply, using exec-based auth so no local kubeconfig file is required.
provider "kubernetes" {
  host                   = module.cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cluster.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.cluster.cluster_name, "--region", "us-east-2"]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.cluster.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.cluster.cluster_name, "--region", "us-east-2"]
    }
  }
}

output "cluster_name" {
  value = module.cluster.cluster_name
}

output "kubeconfig_command" {
  value = module.cluster.kubeconfig_command
}
