# Architecture Guide

## Overview

The platform provisions one isolated EKS cluster per invocation, all in a single
AWS account/region (`us-east-2`), using a shared set of Terraform modules.

```
clusters/ (root module, 1 workspace per cluster)
   └── modules/cluster
         ├── modules/networking   (VPC, subnets, IGW, optional NAT, SGs, NACL)
         ├── modules/iam          (cluster role, node role, instance profile)
         ├── modules/eks          (cluster, OIDC, access entries, node groups)
         ├── modules/addons       (VPC CNI, CoreDNS, kube-proxy, EBS CSI, metrics-server, ALB optional)
         ├── modules/storage      (default gp3 StorageClass)
         └── modules/monitoring   (optional CloudWatch log group)
```

## Networking

- Primary VPC CIDR (`10.0.0.0/16` by default) is used for node/EC2 networking.
- A secondary CIDR (`100.64.0.0/16` by default) is associated with the VPC and
  split into "pod subnets" for custom networking (larger pod IP space,
  separate from node ENIs).
- Public subnets are always created (one per AZ). Private subnets and the NAT
  Gateway are **optional**, controlled by `enable_private_subnets` /
  `enable_nat_gateway` — disabled by default to minimize cost.

## EKS

- Standard support tier only (no extended support).
- `access_config.authentication_mode = API_AND_CONFIG_MAP` — the IAM identity
  that runs `terraform apply` (`aws sts get-caller-identity`) is automatically
  granted `AmazonEKSClusterAdminPolicy` via an EKS access entry.
- CloudWatch control-plane logging is **off by default** (cost) — enable via
  `enable_cluster_logging`.
- Managed node group is the default; an optional self-managed (unmanaged) node
  group backed by an Auto Scaling Group + launch template is available via
  `enable_unmanaged_node_group`.

## State isolation

Each cluster is a separate Terraform **workspace** under `terraform/02-clusters`
using a local backend. This gives each cluster an independent state file
(`terraform.tfstate.d/<cluster_name>/terraform.tfstate`) without any module code
changes, and scales cleanly from 1 to many clusters by adding entries to
`clusters.auto.tfvars.json` and running `create-one.sh`/`create-all.sh`.

## Tagging

Every resource is tagged with `Project, Cluster, Environment, Owner,
AutoDestroy=true` so environments are easy to find and safely bulk
destroy when no longer needed.
