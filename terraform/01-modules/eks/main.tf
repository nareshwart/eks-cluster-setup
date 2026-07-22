terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# EKS Cluster
# ---------------------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name                      = var.cluster_name
  role_arn                  = var.cluster_role_arn
  version                   = var.kubernetes_version
  enabled_cluster_log_types = var.enable_cluster_logging ? ["api", "audit", "authenticator", "controllerManager", "scheduler"] : []

  vpc_config {
    subnet_ids              = var.node_subnet_ids
    security_group_ids      = [var.cluster_security_group_id]
    endpoint_public_access  = true
    endpoint_private_access = var.endpoint_private_access
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# OIDC Provider (for IRSA)
# ---------------------------------------------------------------------------

data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Grant the applying IAM identity (aws sts get-caller-identity) cluster-admin
# ---------------------------------------------------------------------------

resource "aws_eks_access_entry" "caller_identity" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = data.aws_caller_identity.current.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "caller_identity_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = data.aws_caller_identity.current.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.caller_identity]
}

# ---------------------------------------------------------------------------
# Managed Node Group (default)
# ---------------------------------------------------------------------------

resource "aws_eks_node_group" "managed" {
  count           = var.enable_managed_node_group ? 1 : 0
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-managed-ng"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.node_subnet_ids

  instance_types = [var.instance_type]
  capacity_type  = var.capacity_type

  scaling_config {
    desired_size = var.node_count
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ---------------------------------------------------------------------------
# Optional self-managed (unmanaged) node group via EC2 Auto Scaling Group
# ---------------------------------------------------------------------------

data "aws_ssm_parameter" "eks_ami" {
  count = var.enable_unmanaged_node_group ? 1 : 0
  name  = "/aws/service/eks/optimized-ami/${var.kubernetes_version}/amazon-linux-2/recommended/image_id"
}

resource "aws_launch_template" "unmanaged" {
  count         = var.enable_unmanaged_node_group ? 1 : 0
  name_prefix   = "${var.cluster_name}-unmanaged-"
  image_id      = data.aws_ssm_parameter.eks_ami[0].value
  instance_type = var.instance_type

  iam_instance_profile {
    name = var.node_instance_profile_name
  }

  vpc_security_group_ids = [var.cluster_security_group_id]

  user_data = base64encode(<<-EOT
    #!/bin/bash
    /etc/eks/bootstrap.sh ${var.cluster_name}
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.cluster_name}-unmanaged-node" })
  }
}

resource "aws_autoscaling_group" "unmanaged" {
  count               = var.enable_unmanaged_node_group ? 1 : 0
  name                = "${var.cluster_name}-unmanaged-asg"
  desired_capacity    = var.node_count
  min_size            = var.node_min_size
  max_size            = var.node_max_size
  vpc_zone_identifier = var.node_subnet_ids

  launch_template {
    id      = aws_launch_template.unmanaged[0].id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = merge(var.tags, {
      Name                                        = "${var.cluster_name}-unmanaged-node"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  depends_on = [aws_eks_cluster.this]
}
