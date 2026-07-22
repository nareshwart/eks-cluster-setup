# EKS Cluster Platform (Terraform)

Production-grade, reusable Terraform platform for provisioning any number of
isolated EKS clusters, each fully independent and destroyable, from a single
set of modules.

## Repository Structure

```
terraform/
├── backend/                # Remote (S3 + DynamoDB) backend docs/config (optional)
│   └── bootstrap/           # One-time bootstrap: creates S3 bucket + DynamoDB table
├── 01-modules/
│   ├── networking/         # VPC, subnets, IGW, optional NAT, route tables, SGs
│   ├── iam/                # Cluster role, node role, IRSA roles
│   ├── eks/                # EKS cluster, node groups, OIDC, access entries
│   ├── addons/              # VPC CNI, CoreDNS, kube-proxy, EBS CSI, metrics-server, ALB (optional)
│   ├── monitoring/          # Optional CloudWatch log group
│   ├── storage/             # Default gp3 StorageClass
│   └── cluster/ # Composes all modules for one EKS cluster
├── 02-clusters/             # Root module. One Terraform workspace per cluster = isolated state
├── 03-examples/             # Minimal example wiring the cluster module directly
├── 04-automation/           # create-one.sh, destroy-one.sh, create-all.sh, destroy-all.sh, health-check.sh, generate-kubeconfig.sh
├── 05-scripts/              # cost-summary.sh
└── 06-docs/                 # Architecture, Cluster/Operator guides, FAQ, Troubleshooting, Cost
```

## Design

- Region: `us-east-2`
- Kubernetes: latest supported EKS version (default `1.31`, override per cluster)
- Node instance type: `t3.medium`, 3 worker nodes (defaults, overridable)
- Capacity: On-Demand, Managed Node Group by default; optional unmanaged (self-managed) node group
- VPC: primary CIDR for nodes + secondary CIDR for pods (custom networking), NAT Gateway optional
- State isolation: local backend, **one Terraform workspace per cluster** under `02-clusters/`
  (`terraform.tfstate.d/<cluster_name>/terraform.tfstate`). No module code changes needed to scale
  from 1 to many clusters — just add entries to `02-clusters/clusters.auto.tfvars.json`.
- Tagging: every resource is tagged with `Project, Cluster, Environment, Owner, AutoDestroy`.

## Quick Start

```bash
cd terraform/02-clusters
terraform init

# Create one cluster
../04-automation/create-one.sh dev01

# Create all clusters defined in clusters.auto.tfvars.json
../04-automation/create-all.sh

# Get kubeconfig
../04-automation/generate-kubeconfig.sh dev01

# Health check
../04-automation/health-check.sh dev01

# Destroy one / all
../04-automation/destroy-one.sh dev01
../04-automation/destroy-all.sh
```

See [docs/](06-docs/) for detailed guides.
