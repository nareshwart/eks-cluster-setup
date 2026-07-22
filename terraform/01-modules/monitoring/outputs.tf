output "log_group_name" {
  value = try(aws_cloudwatch_log_group.cluster[0].name, null)
}
