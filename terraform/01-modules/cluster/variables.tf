variable "cluster_name" {
  description = "Unique cluster identifier, e.g. dev01"
  type        = string
}

variable "environment" {
  description = "Environment label, e.g. dev, staging, prod"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owner name/team, used for the Owner tag"
  type        = string
  default     = "platform-team"
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}

variable "kubernetes_version" {
  type    = string
  default = "1.35"
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "additional_admin_principal_arns" {
  description = "Extra IAM principal ARNs (users or roles) to grant cluster-admin access, in addition to the identity running `terraform apply`."
  type        = list(string)
  default     = []
}

variable "node_count" {
  type    = number
  default = 3
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "enable_managed_node_group" {
  type    = bool
  default = true
}

variable "enable_unmanaged_node_group" {
  type    = bool
  default = false
}

variable "vpc_cidr" {
  description = "Primary VPC CIDR block used for node networking. Required - no default, to avoid CIDR collisions between clusters."
  type        = string
}

variable "enable_custom_pod_networking" {
  description = "Whether to allocate a secondary CIDR for pod networking"
  type        = bool
  default     = true
}

variable "pod_cidr" {
  description = "Secondary CIDR block for pod networking (custom networking). Required - no default, to avoid CIDR collisions between clusters."
  type        = string
}

variable "az_count" {
  type    = number
  default = 3
}

variable "enable_private_subnets" {
  type    = bool
  default = false
}

variable "enable_nat_gateway" {
  type    = bool
  default = false
}

variable "enable_cluster_logging" {
  type    = bool
  default = false
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "enable_ebs_csi" {
  type    = bool
  default = true
}

variable "enable_metrics_server" {
  type    = bool
  default = true
}

variable "enable_alb_controller" {
  type    = bool
  default = false
}
