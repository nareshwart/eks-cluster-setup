variable "name_prefix" {
  description = "Prefix used for naming all networking resources (e.g. cluster name)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name, used for kubernetes.io/cluster subnet tags"
  type        = string
}

variable "vpc_cidr" {
  description = "Primary VPC CIDR block used for node networking"
  type        = string
}

variable "pod_cidr" {
  description = "Secondary CIDR block for pod networking (custom networking). Empty string disables it."
  type        = string
  default     = ""
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets across"
  type        = number
  default     = 3
}

variable "enable_private_subnets" {
  description = "Whether to create private subnets"
  type        = bool
  default     = false
}

variable "enable_nat_gateway" {
  description = "Whether to create a NAT Gateway (only relevant if private subnets are enabled)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
