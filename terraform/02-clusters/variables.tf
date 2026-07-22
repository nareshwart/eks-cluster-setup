variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Environment label applied to all clusters, e.g. dev, staging, prod"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owner name/team applied to the Owner tag"
  type        = string
  default     = "platform-team"
}

variable "cluster_name" {
  description = "Override for which cluster config to use instead of the Terraform workspace name. Leave empty to use the workspace name."
  type        = string
  default     = ""
}

variable "clusters" {
  description = "Map of cluster_name => cluster configuration. Add/remove entries to scale from 1 to many clusters without touching any module code."
  type = map(object({
    kubernetes_version           = string
    instance_type                = string
    capacity_type                = string
    node_count                   = number
    node_min_size                = number
    node_max_size                = number
    enable_managed_node_group    = bool
    enable_unmanaged_node_group  = bool
    vpc_cidr                     = string
    enable_custom_pod_networking = bool
    pod_cidr                     = string
    enable_private_subnets       = bool
    enable_nat_gateway           = bool
    enable_cluster_logging       = bool
    enable_ebs_csi               = bool
    enable_metrics_server        = bool
    enable_alb_controller        = bool
  }))
  default = {}
}

variable "default_cluster_config" {
  description = "Fallback configuration used when a cluster_name is not present in var.clusters"
  type = object({
    kubernetes_version           = string
    instance_type                = string
    capacity_type                = string
    node_count                   = number
    node_min_size                = number
    node_max_size                = number
    enable_managed_node_group    = bool
    enable_unmanaged_node_group  = bool
    vpc_cidr                     = string
    enable_custom_pod_networking = bool
    pod_cidr                     = string
    enable_private_subnets       = bool
    enable_nat_gateway           = bool
    enable_cluster_logging       = bool
    enable_ebs_csi               = bool
    enable_metrics_server        = bool
    enable_alb_controller        = bool
  })
  default = {
    kubernetes_version           = "1.35"
    instance_type                = "t3.medium"
    capacity_type                = "ON_DEMAND"
    node_count                   = 2
    node_min_size                = 1
    node_max_size                = 3
    enable_managed_node_group    = true
    enable_unmanaged_node_group  = false
    vpc_cidr                     = "10.0.0.0/16"
    enable_custom_pod_networking = true
    pod_cidr                     = "100.64.0.0/16"
    enable_private_subnets       = false
    enable_nat_gateway           = false
    enable_cluster_logging       = false
    enable_ebs_csi               = true
    enable_metrics_server        = true
    enable_alb_controller        = false
  }
}
