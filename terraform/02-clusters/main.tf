# Root module for provisioning ONE EKS cluster per Terraform workspace. The
# active cluster is selected via `terraform workspace select <cluster_name>`
# (automation/create-one.sh does this for you) and its configuration is
# looked up from the `clusters` map variable so that no module code changes
# are needed to scale from 1 cluster to many.

locals {
  workspace = terraform.workspace

  # Fall back to var.cluster_name if set (useful for `-var` overrides / CI),
  # otherwise use the selected workspace name.
  cluster_key = var.cluster_name != "" ? var.cluster_name : local.workspace

  cluster_config = lookup(var.clusters, local.cluster_key, var.default_cluster_config)
}

module "cluster" {
  source = "../01-modules/cluster"

  cluster_name = local.cluster_key
  environment  = var.environment
  owner        = var.owner

  kubernetes_version          = local.cluster_config.kubernetes_version
  instance_type               = local.cluster_config.instance_type
  capacity_type               = local.cluster_config.capacity_type
  node_count                  = local.cluster_config.node_count
  node_min_size               = local.cluster_config.node_min_size
  node_max_size               = local.cluster_config.node_max_size
  enable_managed_node_group   = local.cluster_config.enable_managed_node_group
  enable_unmanaged_node_group = local.cluster_config.enable_unmanaged_node_group

  vpc_cidr                     = local.cluster_config.vpc_cidr
  enable_custom_pod_networking = local.cluster_config.enable_custom_pod_networking
  pod_cidr                     = local.cluster_config.pod_cidr
  enable_private_subnets       = local.cluster_config.enable_private_subnets
  enable_nat_gateway           = local.cluster_config.enable_nat_gateway

  enable_cluster_logging = local.cluster_config.enable_cluster_logging
  enable_ebs_csi         = local.cluster_config.enable_ebs_csi
  enable_metrics_server  = local.cluster_config.enable_metrics_server
  enable_alb_controller  = local.cluster_config.enable_alb_controller
}
