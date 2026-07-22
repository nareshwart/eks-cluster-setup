terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Optional CloudWatch log group for cluster control-plane logs.
# Only useful if enable_cluster_logging = true on the eks module; kept separate
# so log retention/cost can be tuned per cluster without touching the eks module.

resource "aws_cloudwatch_log_group" "cluster" {
  count             = var.enable_monitoring ? 1 : 0
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days

  tags = var.tags
}
