# Operator Guide

## Managing the cluster roster

Edit `terraform/02-clusters/clusters.auto.tfvars.json` to add/remove clusters and
override per-cluster settings (instance type, node count, k8s version, NAT
gateway, ALB controller, etc.). No module code changes are required.

## Bulk operations

```bash
cd terraform

# Create every cluster in clusters.auto.tfvars.json
./automation/create-all.sh

# Destroy every cluster (workspace) that currently exists
./automation/destroy-all.sh

# Health check a specific cluster
./automation/health-check.sh dev07

# Rough cost/resource summary across the account
./scripts/cost-summary.sh us-east-2
```

## Adding a new cluster

1. Add an entry to `clusters.auto.tfvars.json` (copy an existing block, give
   it a unique `vpc_cidr`/`pod_cidr` to avoid overlap if VPC peering is ever
   needed).
2. Run `./automation/create-one.sh <cluster_name>`.

## Tearing everything down

```bash
./automation/destroy-all.sh
```

All resources are tagged `AutoDestroy=true`; `scripts/cost-summary.sh` can be
used beforehand to confirm what will be removed, and afterward to confirm
nothing tagged `Project=EKS-Training` remains running.
