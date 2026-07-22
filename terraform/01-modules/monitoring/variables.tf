variable "cluster_name" {
  type = string
}

variable "enable_monitoring" {
  description = "Create CloudWatch log group for the cluster. Disabled by default to save cost."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}
