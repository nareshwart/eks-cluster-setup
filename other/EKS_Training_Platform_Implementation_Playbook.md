# EKS Training Platform - Implementation Playbook

## Project Goal

Build a reusable, production-quality **EKS Training Platform** that
allows **25--40 students** to provision and destroy their own AWS
infrastructure using Terraform.

### Objectives

-   Modular architecture
-   Production-grade Terraform
-   Reusable for future batches
-   Cost optimized
-   Fully automated
-   Easily extensible

------------------------------------------------------------------------

# High-Level Architecture

``` text
AWS Account (us-east-2)
│
├── Terraform Backend (S3 + DynamoDB)
│
└── Student Environments
    ├── Student01
    │   ├── VPC
    │   ├── EKS
    │   ├── Managed Node Group
    │   └── Add-ons
    ├── Student02
    ├── Student03
    └── Student25
```

## Design Principles

-   Everything must be Infrastructure as Code.
-   Students should never manually create AWS resources.
-   Every environment must be isolated.
-   Every resource must be tagged.
-   Entire environments must be removable with Terraform.
-   No manual AWS Console operations after initial setup.

------------------------------------------------------------------------

# Repository Structure

``` text
eks-training-platform/
├── backend/
├── bootstrap/
├── modules/
│   ├── networking/
│   ├── eks/
│   ├── addons/
│   ├── iam/
│   ├── monitoring/
│   ├── storage/
│   └── student-environment/
├── automation/
├── scripts/
├── students/
├── docs/
├── examples/
└── README.md
```

------------------------------------------------------------------------

# Phase 0 -- Architecture Planning

## Deliverables

-   Naming convention
-   Tagging strategy
-   Terraform version
-   AWS Provider version
-   Kubernetes version
-   AWS Region
-   Instance type
-   Node count
-   Remote backend

### Decisions

-   Region: us-east-2
-   Terraform: Latest stable
-   AWS Provider: Latest
-   Kubernetes: Latest supported EKS version
-   Instance Type: t3.medium
-   Worker Nodes: 3
-   Capacity Type: On-Demand

------------------------------------------------------------------------

# Phase 1 -- Repository Skeleton

**Goal:** Create only the repository structure.

**Prompt to Codex**

> Create a production-grade Terraform repository structure following
> Terraform best practices.

------------------------------------------------------------------------

# Phase 2 -- Backend Infrastructure

Create:

-   S3 bucket for Terraform state
-   DynamoDB table for state locking

Example:

``` text
terraform-state/
├── student01.tfstate
├── student02.tfstate
└── student03.tfstate
```

Acceptance: - Remote state works - Locking works - Each student has
isolated state

------------------------------------------------------------------------

# Phase 3 -- Networking Module

Create reusable module for:

-   VPC
-   Public Subnets
-   Private Subnets
-   NAT Gateway
-   Internet Gateway
-   Route Tables
-   NACLs
-   Security Groups

Outputs:

-   VPC ID
-   Public Subnet IDs
-   Private Subnet IDs
-   NAT Gateway ID

------------------------------------------------------------------------

# Phase 4 -- EKS Module

Create reusable module for:

-   EKS Cluster
-   Managed Node Group
-   IAM Roles
-   OIDC Provider
-   CloudWatch Logging

Outputs:

-   Cluster Name
-   Endpoint
-   Certificate
-   OIDC
-   Node Group

Acceptance:

``` bash
kubectl get nodes
```

------------------------------------------------------------------------

# Phase 5 -- Add-ons

Install:

-   VPC CNI
-   CoreDNS
-   kube-proxy
-   EBS CSI Driver
-   Metrics Server

Optional:

-   AWS Load Balancer Controller

Do not implement yet:

-   ArgoCD
-   Istio
-   Karpenter

------------------------------------------------------------------------

# Phase 6 -- Student Environment Module

Inputs:

-   student_name
-   cluster_name
-   instance_type
-   node_count
-   kubernetes_version

Outputs:

-   kubeconfig
-   cluster endpoint
-   cluster ARN

------------------------------------------------------------------------

# Phase 7 -- Multi-Student Support

Implement `for_each` support.

Goal:

-   1 cluster
-   5 clusters
-   25 clusters
-   40 clusters

without changing module code.

------------------------------------------------------------------------

# Phase 8 -- Tagging Strategy

Required tags:

-   Project
-   Batch
-   Student
-   Trainer
-   Environment
-   Owner
-   AutoDestroy

Example:

``` text
Project=EKS-Training
Batch=July2026
Student=student01
Trainer=Nareshwar
Environment=Lab
AutoDestroy=true
```

------------------------------------------------------------------------

# Phase 9 -- Cost Optimization

Configure:

-   Delete on termination
-   EBS cleanup
-   Log retention
-   Disable deletion protection
-   Force destroy where appropriate

------------------------------------------------------------------------

# Phase 10 -- Automation

Create:

-   create-one.sh
-   destroy-one.sh
-   create-all.sh
-   destroy-all.sh
-   health-check.sh
-   generate-kubeconfig.sh

------------------------------------------------------------------------

# Phase 11 -- Student Experience

Students should only run:

``` bash
terraform apply
```

or

``` bash
./create-one.sh student01
```

------------------------------------------------------------------------

# Phase 12 -- Instructor Experience

Automation should support:

-   Create all environments
-   Destroy all environments
-   Health check
-   Export kubeconfigs
-   Cost summary

------------------------------------------------------------------------

# Phase 13 -- CI/CD

Pipeline:

1.  terraform fmt
2.  terraform validate
3.  terraform plan
4.  tfsec / Checkov
5.  Manual apply

------------------------------------------------------------------------

# Phase 14 -- Documentation

Create:

-   Architecture Guide
-   Student Guide
-   Trainer Guide
-   Troubleshooting
-   FAQ
-   Cost Estimation

------------------------------------------------------------------------

# Phase 15 -- Future Enhancements

Prepare extension points for:

-   Karpenter
-   ArgoCD
-   Velero
-   Prometheus
-   Grafana
-   Istio
-   ExternalDNS
-   Cert Manager
-   EFS CSI
-   Crossplane

------------------------------------------------------------------------

# Recommended Development Order

1.  Repository
2.  Backend
3.  Networking
4.  IAM
5.  EKS
6.  Node Groups
7.  Outputs
8.  Add-ons
9.  Student Module
10. Multi-Student Support
11. Automation
12. CI/CD
13. Documentation
14. Enhancements

------------------------------------------------------------------------

# Working with Codex

For every phase:

1.  Start a new Codex chat.
2.  Scope only one phase.
3.  Generate code.
4.  Review.
5.  Test.
6.  Commit to Git.
7.  Move to the next phase only after successful validation.

Avoid asking Codex to generate the complete platform in one prompt.

------------------------------------------------------------------------

# Definition of Done

-   Any number of student environments can be created.
-   Every environment is isolated.
-   Students can create and destroy their own environment.
-   Instructor can create/destroy all environments.
-   Remote state is used.
-   CI/CD validates changes.
-   Documentation is complete.
