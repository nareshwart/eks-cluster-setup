# EKS Cluster Platform using Terraform — Lab Guide

> **Region**: All resources in this lab are provisioned in `us-east-2` (Ohio).  
> **Model**: We use the single-cluster example under the `03-examples/single-cluster/` directory. This is the simplest way to provision a single EKS cluster using reusable modules.
> **Repo location**: The repo is cloned to `$HOME/eks-cluster-setup`. Each step below starts with the exact `cd` command you need.

---

## Overview

```
Step 0 → Setup Prerequisites & AWS Access
Step 1 → Explore Example Structure & Config
Step 2 → Customize the Cluster Configuration
Step 3 → Initialize & Provision EKS Cluster
Step 4 → Configure Kubeconfig & Verify Access
Step 5 → Verify Custom Pod Networking
Step 6 → Deploy a Sample App (Nginx + ALB Ingress)
Step 7 → Perform Cleanup & Destroy
```

---

## Step 0 — Get the Repo and Install Tools

### Step 0a — Clone the repository (if not already done)

```bash
cd $HOME
git clone https://github.com/nareshwart/eks-cluster-setup.git
```

> **Already have the repo?** Pull the latest changes:
> ```bash
> cd $HOME/eks-cluster-setup
> git pull
> ```

---

### Step 0b — Install all prerequisite tools

All required tools (`terraform`, `aws`, `kubectl`, `helm`, `eksctl`) are installed by a single script in the `00-prerequisites/` folder.

```bash
cd $HOME/eks-cluster-setup/00-prerequisites
bash install-all.sh
```

---

### Step 0c — AWS credentials

Choose the credentials option that applies to your setup:

*   **Option A (IAM Instance Profile / EC2 Jump Box)**: If you are running on an EC2 jump box, a role has already been attached. Verify access directly:
    ```bash
    aws sts get-caller-identity
    ```
*   **Option B (Local Machine)**: If running locally, configure manually:
    ```bash
    aws configure
    ```

---

## Step 1 — Explore Configurations

Before provisioning, navigate to the single-cluster example directory:

```bash
cd $HOME/eks-cluster-setup/terraform/03-examples/single-cluster
```

Open `main.tf` to inspect the configuration:

*   **Region**: The AWS provider defaults to `us-east-2`.
*   **Module wiring**: It references the shared EKS platform module (`../../01-modules/cluster`).
*   **Kubernetes version**: Defaults to `1.36` (controlled by base module variable defaults).
*   **Instance type**: Defaults to `t3.small` with a node count of `2` (min 2, max 3).
*   **Network config**: Sets up nodes directly in public subnets with public IPs (to save NAT Gateway costs in training/lab setups). It configures VPC custom networking with a secondary CIDR for pods.

---

## Step 2 — Customize the Configuration

Before running any Terraform commands, edit `main.tf` to customize it with your assigned **student name** and a **unique VPC CIDR block** to avoid clashes in shared AWS accounts.

```bash
cd $HOME/eks-cluster-setup/terraform/03-examples/single-cluster
```

Edit `main.tf` (e.g. using `nano main.tf` or `vi main.tf`) and update the `module "cluster"` block:

```hcl
module "cluster" {
  source = "../../01-modules/cluster"

  cluster_name = "student1"             # <-- Change to your assigned student name
  environment  = "dev"
  owner        = "platform-team"

  instance_type = "t3.small"
  node_count    = 2

  # Pick a unique CIDR range per student to prevent collisions
  vpc_cidr = "10.50.0.0/16"             # <-- E.g., student1: 10.50.0.0/16, student2: 10.51.0.0/16
  pod_cidr = "100.64.0.0/16"            # <-- E.g., student1: 100.64.0.0/16, student2: 100.65.0.0/16

  additional_admin_principal_arns = []
}
```

Save the file and exit.

---

## Step 3 — Initialize and Apply (Provision EKS)

Ensure you are in the single-cluster example directory:

```bash
cd $HOME/eks-cluster-setup/terraform/03-examples/single-cluster
```

### Initialize Terraform providers
```bash
terraform init
```

### Preview the changes (Optional)
```bash
terraform plan
```

### Provision the EKS Cluster
```bash
terraform apply -auto-approve
```

⏱️ **This takes 15–20 minutes.** Terraform will deploy the VPC, IAM roles, EKS control plane, node groups, and cluster add-ons.

---

## Step 4 — Configure Kubeconfig & Verify Access

After the apply successfully completes, generate a local kubeconfig file so `kubectl` can communicate with your new cluster.

```bash
cd $HOME/eks-cluster-setup/terraform/03-examples/single-cluster

# Update your kubeconfig (replace student1 with your cluster_name)
aws eks update-kubeconfig --name eks-student1-cluster --region us-east-2
```

Verify connection:
```bash
kubectl get nodes
```

**Expected output:**
```
NAME                                          STATUS   ROLES    AGE   VERSION
ip-10-50-1-xxx.us-east-2.compute.internal    Ready    <none>   2m    v1.36.x
ip-10-50-2-xxx.us-east-2.compute.internal    Ready    <none>   2m    v1.36.x
```

---

## Step 5 — Verify Custom Pod Networking

By default, the platform custom networking places pods in the secondary CIDR (`100.64.x.x`) to leave your node subnets free.

**Verify ENIConfigs are present:**
```bash
kubectl get eniconfig
```

**Test pod IP allocation:**
Spin up a test pod and verify it receives a secondary CIDR IP:

```bash
# Run test pod
kubectl run netcheck --image=public.ecr.aws/nginx/nginx:stable --restart=Never
kubectl wait pod/netcheck --for=condition=Ready --timeout=60s

# Check Pod IP
kubectl get pod netcheck -o wide
```

Expected output:
*   **Pod IP**: Should fall inside the `100.64.x.x` range.
*   **Node IP**: Should remain inside the `10.50.x.x` range.

```bash
# Clean up test pod
kubectl delete pod netcheck
```

---

## Step 6 — Deploy a Sample Application

Let's deploy a service and expose it. Since the platform module installs the AWS Load Balancer Controller, we can expose our app via an Application Load Balancer (ALB).

Navigate to the sample application directory:
```bash
cd $HOME/eks-cluster-setup/eksctl/05-applications
```

### Apply Deployment & Service
```bash
kubectl apply -f nginx.yaml
```

### Expose with ALB Ingress
```bash
kubectl apply -f ingress.yaml
```

Watch the Ingress allocation until the external address is populated (~2 minutes):
```bash
kubectl get ingress nginx -w
```

Once the `ADDRESS` is shown (e.g., `k8s-default-nginx-xxx.us-east-2.elb.amazonaws.com`), paste it into your browser to verify it connects to the Welcome page.

---

## Step 7 — Tear Down & Cleanup

> [!WARNING]
> Always delete any Kubernetes `Ingress` resources before running Terraform destroy. Otherwise, the Load Balancer Controller will leave orphan ALBs/Target Groups behind, which will block Terraform from deleting the VPC.

### 1. Delete Ingress resource first
```bash
cd $HOME/eks-cluster-setup/eksctl/05-applications
kubectl delete -f ingress.yaml

# Wait until the ALB is fully deleted in AWS (approx 2 minutes)
kubectl get ingress nginx -w
```

### 2. Destroy EKS Cluster with Terraform

```bash
cd $HOME/eks-cluster-setup/terraform/03-examples/single-cluster

# Destroy the EKS Cluster and all its AWS infrastructure
terraform destroy -auto-approve
```

⏱️ **This takes ~15 minutes.** Once finished, all resources created by Terraform in this lab will be deleted.
