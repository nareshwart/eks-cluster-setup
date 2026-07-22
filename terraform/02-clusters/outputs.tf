output "cluster_name" {
  value = module.cluster.cluster_name
}

output "cluster_endpoint" {
  value = module.cluster.cluster_endpoint
}

output "cluster_arn" {
  value = module.cluster.cluster_arn
}

output "vpc_id" {
  value = module.cluster.vpc_id
}

output "kubeconfig_command" {
  value = module.cluster.kubeconfig_command
}
