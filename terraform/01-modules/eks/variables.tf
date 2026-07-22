variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

variable "cluster_role_arn" {
  type = string
}

variable "node_role_arn" {
  type = string
}

variable "node_instance_profile_name" {
  type = string
}

variable "node_subnet_ids" {
  type = list(string)
}

variable "cluster_security_group_id" {
  type = string
}

variable "endpoint_private_access" {
  type    = bool
  default = false
}

variable "enable_cluster_logging" {
  description = "Enable CloudWatch control-plane logging. Disabled by default to control cost."
  type        = bool
  default     = false
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "capacity_type" {
  type    = string
  default = "ON_DEMAND"
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
  default = 5
}

variable "enable_managed_node_group" {
  type    = bool
  default = true
}

variable "enable_unmanaged_node_group" {
  description = "Optional self-managed (unmanaged) node group, in addition to / instead of the managed one"
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
