# Optional Remote Backend

By default this platform uses a **local backend** (`clusters/backend.tf`) with one
Terraform workspace per cluster, giving isolated state files under
`clusters/terraform.tfstate.d/<cluster_name>/terraform.tfstate`.

If you want a remote backend (S3 + DynamoDB) instead — e.g. for a shared operator
machine or CI — run `terraform/backend/bootstrap` once to create the bucket and lock table,
then switch `clusters/backend.tf` to the `s3` block below and re-run `terraform init -migrate-state`.

```hcl
terraform {
  backend "s3" {
    bucket         = "eks-platform-tfstate-<account-id>"
    key            = "clusters/<cluster_name>.tfstate"
    region         = "us-east-2"
    dynamodb_table = "eks-platform-tf-locks"
    encrypt        = true
  }
}
```

Each cluster gets a distinct `key`, so state remains isolated even on a shared backend.
