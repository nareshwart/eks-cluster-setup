# EKS Cluster Platform using Terraform — Lab Guide

> **Region**: All resources in this lab are provisioned in `us-east-2` (Ohio).  
> **Workspace Model**: We use **Terraform Workspaces** under the `02-clusters/` directory to manage multiple EKS clusters cleanly. This isolates state files and resource namespaces without needing duplicate code.  
> **Repo location**: The repo is cloned to `$HOME/eks-cluster-setup`. Each step below starts with the exact `cd` command you need.

---

## Overview

```
Step 0 → Setup Prerequisites & AWS Access
Step 1 → Explore Terraform Structures & Configuration
Step 2 → Initialize Terraform & Workspaces
Step 3 → Apply and Provision EKS Cluster
Step 4 → Generate Kubeconfig & Verify Access
Step 5 → Run Health & Deployment Checks
Step 6 → Deploy a Sample App (Nginx + ALB Ingress)
Step 7 → Perform Safe Cleanup & Destroy
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

Before provisioning, navigate to the clusters configuration directory:

```bash
cd $HOME/eks-cluster-setup/terraform/02-clusters
```

Open `clusters.auto.tfvars.json` to inspect the available workspaces:

```json
{
  "clusters": {
    "dev01": {
      "kubernetes_version": "1.31",
      "instance_type": "t3.medium",
      "capacity_type": "ON_DEMAND",
      "node_count": 3,
      "node_min_size": 1,
      "node_max_size": 5,
      "enable_managed_node_group": true,
      "enable_unmanaged_node_group": false,
      "vpc_cidr": "10.0.0.0/16",
      "enable_custom_pod_networking": true,
      "pod_cidr": "100.64.0.0/16",
      "enable_private_subnets": false,
      "enable_nat_gateway": false,
      "enable_cluster_logging": false,
      "enable_ebs_csi": true,
      "enable_metrics_server": true,
      "enable_alb_controller": false
    }
  }
}
```

> [!NOTE]
> Since this is a training environment running 8h/day, `enable_private_subnets` and `enable_nat_gateway` are set to `false`. This launches nodes directly in public subnets with public IPs to save NAT Gateway costs (~$32+/month).

---

## Step 2 — Initialize and Set Up Workspaces

Navigate to the workspace deployment directory:

```bash
cd $HOME/eks-cluster-setup/terraform/02-clusters
```

### Initialize Terraform providers and backend
```bash
terraform init
```

### Create and switch to a workspace
We use the cluster name as the workspace name. For example, to set up `dev01`:

```bash
# Check existing workspaces
terraform workspace list

# Create a new workspace named dev01
terraform workspace new dev01

# Select the workspace (if it already exists)
terraform workspace select dev01
```

---

## Step 3 — Apply and Provision the Cluster

Ensure you are in the workspace directory:

```bash
cd $HOME/eks-cluster-setup/terraform/02-clusters
```

We will use the automation wrapper scripts to provision our cluster. The wrapper script handles workspace selecting and triggers the apply cleanly.

```bash
# Run the create-one script with your workspace name (e.g., dev01)
../04-automation/create-one.sh dev01
```

> **Alternative (Vanilla Terraform)**:
> If you prefer not to use the wrapper, you can run:
> ```bash
> terraform apply -var="cluster_name=dev01"
> ```

⏱️ **This takes 15–20 minutes.** Terraform will deploy VPC subnets, IAM Roles, EKS Control Plane, Node Groups, and Kubernetes add-ons.

---

## Step 4 — Generate Kubeconfig & Verify Access

After the deployment successfully completes, we need to generate a kubeconfig file to let `kubectl` authenticate with the new cluster.

```bash
cd $HOME/eks-cluster-setup/terraform/02-clusters

# Generate the workspace-specific kubeconfig
../04-automation/generate-kubeconfig.sh dev01
```

Point your environment to the generated kubeconfig file:

```bash
export KUBECONFIG=$(pwd)/kubeconfig-dev01
```

Verify connection:
```bash
kubectl get nodes
```

**Expected output:**
```
NAME                                          STATUS   ROLES    AGE   VERSION
ip-10-0-1-xxx.us-east-2.compute.internal     Ready    <none>   2m    v1.31.x
ip-10-0-2-xxx.us-east-2.compute.internal     Ready    <none>   2m    v1.31.x
```

---

## Step 5 — Run Cluster Health Checks

Verify all system resources are healthy.

```bash
cd $HOME/eks-cluster-setup/terraform/02-clusters

# Run the health check wrapper
../04-automation/health-check.sh dev01
```

### Step 5a — Verify custom pod networking

The terraform EKS module installs and configures the VPC CNI with custom networking enabled by default (`enable_custom_pod_networking: true`).

**Verify ENIConfigs are present:**
```bash
kubectl get eniconfig
```

**Test pod IP allocation:**
Spin up a test pod and verify it receives a secondary CIDR IP (`100.64.x.x`) instead of a primary node subnet IP (`10.0.x.x`):

```bash
# Run test pod
kubectl run netcheck --image=public.ecr.aws/nginx/nginx:stable --restart=Never
kubectl wait pod/netcheck --for=condition=Ready --timeout=60s

# Check Pod IP
kubectl get pod netcheck -o wide
```

Expected output:
*   **Pod IP**: Should fall inside the `100.64.x.x` range.
*   **Node IP**: Should remain inside the `10.0.x.x` range.

```bash
# Clean up test pod
kubectl delete pod netcheck
```

---

## Step 6 — Deploy a Sample Application

Let's deploy a service and expose it. Since the Terraform setup installs the AWS Load Balancer Controller if enabled, we will expose our app via an Application Load Balancer (ALB).

Ensure you are using the correct kubeconfig:
```bash
export KUBECONFIG=$HOME/eks-cluster-setup/terraform/02-clusters/kubeconfig-dev01
```

Navigate to the sample application directory:
```bash
cd $HOME/eks-cluster-setup/eksctl/05-applications
```

### Apply Deployment & ClusterIP Service
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

```bash
# 1. Ensure you are using the correct kubeconfig
export KUBECONFIG=$HOME/eks-cluster-setup/terraform/02-clusters/kubeconfig-dev01

# 2. Delete the ingress resource
cd $HOME/eks-cluster-setup/eksctl/05-applications
kubectl delete -f ingress.yaml

# Wait until the ALB is fully deleted in AWS (approx 2 minutes)
kubectl get ingress nginx -w
```

### Option A — TMUX Detached Destroy (Resilient)

Terraform destroys can take up to 15 minutes. If your SSH connection drops, a running destroy could terminate midway, creating state problems. We recommend running the resilient script which wraps the destroy in a `tmux` or `nohup` session:

```bash
cd $HOME/eks-cluster-setup/terraform/02-clusters

# Start the detached destroy session
../04-automation/destroy-one-resilient.sh dev01

# Monitor the session status
../04-automation/destroy-one-resilient.sh dev01 --status

# Attach to the tmux session to watch progress
../04-automation/destroy-one-resilient.sh dev01 --attach
```

### Option B — Standard Destroy

If you have a stable connection and want to run it inline:

```bash
cd $HOME/eks-cluster-setup/terraform/02-clusters

# Run the standard destroy wrapper
../04-automation/destroy-one.sh dev01
```

Once complete, verify that the workspace state has been removed:
```bash
terraform workspace list
```
