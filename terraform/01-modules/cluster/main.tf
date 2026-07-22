terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  name_prefix  = "eks-${var.cluster_name}"
  cluster_name = "${local.name_prefix}-cluster"

  required_tags = {
    Project     = "EKS-Platform"
    Cluster     = var.cluster_name
    Environment = var.environment
    Owner       = var.owner
    AutoDestroy = "true"
  }

  tags = merge(local.required_tags, var.extra_tags)
}

module "networking" {
  source = "../networking"

  name_prefix            = local.name_prefix
  cluster_name           = local.cluster_name
  vpc_cidr               = var.vpc_cidr
  pod_cidr               = var.enable_custom_pod_networking ? var.pod_cidr : ""
  az_count               = var.az_count
  enable_private_subnets = var.enable_private_subnets
  enable_nat_gateway     = var.enable_nat_gateway
  tags                   = local.tags
}

module "iam" {
  source = "../iam"

  name_prefix = local.name_prefix
  tags        = local.tags
}

module "eks" {
  source = "../eks"

  cluster_name                = local.cluster_name
  kubernetes_version          = var.kubernetes_version
  cluster_role_arn            = module.iam.cluster_role_arn
  node_role_arn               = module.iam.node_role_arn
  node_instance_profile_name  = module.iam.node_instance_profile_name
  node_subnet_ids             = module.networking.node_subnet_ids
  cluster_security_group_id   = module.networking.cluster_security_group_id
  endpoint_private_access     = var.enable_private_subnets
  enable_cluster_logging      = var.enable_cluster_logging
  instance_type               = var.instance_type
  capacity_type               = var.capacity_type
  node_count                  = var.node_count
  node_min_size               = var.node_min_size
  node_max_size               = var.node_max_size
  enable_managed_node_group   = var.enable_managed_node_group
  enable_unmanaged_node_group = var.enable_unmanaged_node_group
  tags                        = local.tags
}

module "addons" {
  source = "../addons"

  name_prefix             = local.name_prefix
  cluster_name            = module.eks.cluster_name
  oidc_provider_arn       = module.eks.oidc_provider_arn
  oidc_provider_url       = module.eks.oidc_provider_url
  managed_node_group_name = module.eks.managed_node_group_name
  enable_ebs_csi          = var.enable_ebs_csi
  enable_metrics_server   = var.enable_metrics_server
  enable_alb_controller   = var.enable_alb_controller
  tags                    = local.tags
}

module "storage" {
  source = "../storage"

  create_default_storage_class = var.enable_ebs_csi

  depends_on = [module.addons]
}

module "monitoring" {
  source = "../monitoring"

  cluster_name       = module.eks.cluster_name
  enable_monitoring  = var.enable_cluster_logging
  log_retention_days = var.log_retention_days
  tags               = local.tags
}
