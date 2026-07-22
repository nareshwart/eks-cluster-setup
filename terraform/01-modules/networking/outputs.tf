output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "pod_subnet_ids" {
  value = aws_subnet.pods[*].id
}

output "nat_gateway_id" {
  value = try(aws_nat_gateway.this[0].id, null)
}

output "cluster_security_group_id" {
  value = aws_security_group.cluster.id
}

# Node network subnets = public (+ private if enabled). Used by EKS/node groups.
output "node_subnet_ids" {
  value = var.enable_private_subnets ? concat(aws_subnet.public[*].id, aws_subnet.private[*].id) : aws_subnet.public[*].id
}
