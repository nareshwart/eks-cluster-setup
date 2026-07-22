variable "name_prefix" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type = string
}

variable "managed_node_group_name" {
  description = "Used only to sequence addon creation after node group is ready"
  type        = string
  default     = null
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
  description = "Optional AWS Load Balancer Controller"
  type        = bool
  default     = false
}

variable "alb_controller_chart_version" {
  type    = string
  default = "1.8.1"
}

variable "tags" {
  type    = map(string)
  default = {}
}
