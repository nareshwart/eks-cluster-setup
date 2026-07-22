terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

# ---------------------------------------------------------------------------
# VPC (primary CIDR for nodes) + secondary CIDR for pods (custom networking)
# ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

resource "aws_vpc_ipv4_cidr_block_association" "pods" {
  count      = var.pod_cidr != "" ? 1 : 0
  vpc_id     = aws_vpc.this.id
  cidr_block = var.pod_cidr
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-igw"
  })
}

# ---------------------------------------------------------------------------
# Public subnets (node network) - always created
# ---------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count                   = length(local.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                                        = "${var.name_prefix}-public-${local.azs[count.index]}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Private subnets (optional, node network)
# ---------------------------------------------------------------------------

resource "aws_subnet" "private" {
  count             = var.enable_private_subnets ? length(local.azs) : 0
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + length(local.azs))
  availability_zone = local.azs[count.index]

  tags = merge(var.tags, {
    Name                                        = "${var.name_prefix}-private-${local.azs[count.index]}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# ---------------------------------------------------------------------------
# Pod subnets (secondary CIDR, used for custom networking / ENIConfig)
# ---------------------------------------------------------------------------

resource "aws_subnet" "pods" {
  count             = var.pod_cidr != "" ? length(local.azs) : 0
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.pod_cidr, 4, count.index)
  availability_zone = local.azs[count.index]

  depends_on = [aws_vpc_ipv4_cidr_block_association.pods]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-pods-${local.azs[count.index]}"
  })
}

# ---------------------------------------------------------------------------
# NAT Gateway (optional) - only needed if private subnets must reach internet
# ---------------------------------------------------------------------------

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-eip"
  })
}

resource "aws_nat_gateway" "this" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  count  = var.enable_private_subnets ? 1 : 0
  vpc_id = aws_vpc.this.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.this[0].id
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  count          = var.enable_private_subnets ? length(aws_subnet.private) : 0
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}

resource "aws_route_table_association" "pods" {
  count          = var.pod_cidr != "" ? length(aws_subnet.pods) : 0
  subnet_id      = aws_subnet.pods[count.index].id
  route_table_id = var.enable_private_subnets ? aws_route_table.private[0].id : aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Security groups
# ---------------------------------------------------------------------------

resource "aws_security_group" "cluster" {
  name_prefix = "${var.name_prefix}-cluster-"
  description = "Additional security group for EKS cluster control-plane ENIs"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-cluster-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_network_acl" "this" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = concat(aws_subnet.public[*].id, aws_subnet.private[*].id, aws_subnet.pods[*].id)

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nacl"
  })
}
