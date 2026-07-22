output "storage_class_name" {
  value = try(kubernetes_storage_class.gp3_default[0].metadata[0].name, null)
}
