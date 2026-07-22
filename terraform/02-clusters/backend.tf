# Local backend: one Terraform workspace per cluster gives isolated state at
# terraform.tfstate.d/<cluster_name>/terraform.tfstate. Switch to the S3 backend
# documented in ../backend/README.md if a shared/remote backend is preferred.

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
