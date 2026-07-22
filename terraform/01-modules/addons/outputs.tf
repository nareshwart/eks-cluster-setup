output "ebs_csi_role_arn" {
  value = try(aws_iam_role.ebs_csi[0].arn, null)
}

output "alb_controller_role_arn" {
  value = try(aws_iam_role.alb_controller[0].arn, null)
}
