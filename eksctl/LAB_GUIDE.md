# EKS using Eksctl — Lab Guide

> **Region**: All scripts in this lab use `us-east-2` (Ohio) as the fixed region.  
> **Cluster name**: Use your assigned name, e.g. `student1`. Replace every occurrence of `student1` below with your actual cluster name.  
> **Repo location**: The repo is cloned to `$HOME/eks-cluster-setup`. Each step below starts with the exact `cd` command you need.

---

## Overview

```
Step 0 → Clone the repo & install prerequisites
Step 1 → Create VPC                    (01-network/)
Step 2 → Generate Cluster Config       (02-eks/)
Step 3 → Create EKS Cluster            (02-eks/)
Step 4 → Configure kubeconfig          (02-eks/)
Step 5 → Post-Creation Verification
Step 6 → Enable Custom Pod Networking   (03-custom-networking/)
Step 7 → Install Add-ons               (04-addons/)
Step 8 → Deploy a Sample App           (05-applications/)
Step 9 → Day-2 Commands
Step 10 → Cleanup                      (cleanup/)
```

---

## Step 0 — Get the Repo and Install Tools

### Step 0a — Clone the repository

```bash
cd $HOME
git clone https://github.com/nareshwart/eks-cluster-setup.git
```

This creates the repo at `$HOME/eks-cluster-setup`.

> **Already have the repo?** Just pull the latest changes:
> ```bash
> cd $HOME/eks-cluster-setup
> git pull
> ```

---

## Prerequisites

### Step 0b — Install all prerequisite tools

All required tools are installed by a single script in the `00-prerequisites/` folder at the repo root. Each individual script is idempotent — if a tool is already installed it prints the version and skips reinstallation, so it is safe to re-run at any time.

**Run from the repo root:**

```bash
cd $HOME/eks-cluster-setup/00-prerequisites
bash install-all.sh
```

**Tools installed (in order):**

| Tool | Script | Purpose |
|---|---|---|
| `git` | `install-git.sh` | Clone / manage the repo |
| `aws` (AWS CLI v2) | `install-aws-cli.sh` | All AWS API calls; macOS uses Homebrew |
| Session Manager Plugin | `install-session-manager-plugin.sh` | SSM-based node access without SSH keys |
| `kubectl` | `install-kubectl.sh` | Kubernetes CLI |
| `helm` | `install-helm.sh` | Helm chart deployments (ALB Controller) |
| `eksctl` | `install-eksctl.sh` | EKS cluster lifecycle management |
| `terraform` | `install-terraform.sh` | Infrastructure as code (used in terraform/ path) |

> **macOS users:** The scripts use [Homebrew](https://brew.sh) (`brew`) for macOS installs. If Homebrew is not installed, install it first:
> ```bash
> /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
> ```

**Expected final output from `install-all.sh`:**
```
==================================================
All prerequisites installed successfully.
```

If any script fails, fix the reported issue and re-run `install-all.sh` — it is safe to run again.

---

### Step 0c — AWS credentials

AWS credentials can be set up in one of two ways. **Use whichever applies to you.**

---

#### ✅ Option A — IAM Instance Profile (Jump Box) — *most students*

Your EC2 jump box already has an **IAM instance profile** attached with all required permissions. No credential configuration is needed — the AWS CLI automatically picks up the role from the instance metadata.

Verify it is working:

```bash
aws sts get-caller-identity
```

> If this returns your account ID and an IAM role ARN (not a user), you are good to go — skip to Step 0d.

---

#### 🔧 Option B — Manual credentials (local machine or fresh EC2)

If you are running on your **own laptop** or an EC2 without an instance profile, configure credentials manually:

```bash
aws configure
```

You will be prompted for:

```
AWS Access Key ID     [None]: <your-access-key>
AWS Secret Access Key [None]: <your-secret-key>
Default region name   [None]: us-east-2
Default output format [None]: json
```

> Ask your trainer for the Access Key and Secret Key if you do not have them.

---

### Step 0d — Verify everything is ready

```bash
# Confirm AWS access and your identity
aws sts get-caller-identity
```

> **Expected output:**
> ```json
> {
>   "UserId": "AIDA...",
>   "Account": "123456789012",
>   "Arn": "arn:aws:iam::123456789012:user/student1"
> }
> ```

```bash
# Quick version check for all tools
git --version
aws --version
eksctl version       # should be >= 0.180
kubectl version --client --output=yaml | grep gitVersion
helm version --short
terraform version
```

---

## Step 1 — Create the VPC

The VPC script creates all networking resources required by EKS.

```bash
# Move into the eksctl folder — start of every lab step
cd $HOME/eks-cluster-setup/eksctl

./01-network/create-vpc.sh us-east-2 student1 10.50.0.0/16
```

**What gets created:**

| Resource | Detail |
|---|---|
| VPC | `10.50.0.0/16` with DNS support and DNS hostnames enabled |
| Secondary CIDR | `100.64.0.0/16` for pod networking (custom networking) |
| Internet Gateway | Attached to the VPC |
| 3 × Public subnets | `10.50.1.0/24`, `10.50.2.0/24`, `10.50.3.0/24` — one per AZ |
| 3 × Pod subnets | `100.64.1.0/24`, `100.64.2.0/24`, `100.64.3.0/24` — one per AZ |
| Public route table | Routes `0.0.0.0/0` → Internet Gateway |
| Pod route table | Local routing only (no internet egress by default) |
| Subnet tags | `kubernetes.io/role/elb=1` on public subnets; `kubernetes.io/role/internal-elb=1` on pod subnets |

> **Save the script output!** You will need `VPC_ID` in later steps.

```
# Example output — your IDs will differ
VPC_ID=vpc-0abc1234567890def
REGION=us-east-2
CLUSTER_NAME=student1
PUBLIC_SUBNETS=subnet-0aaa111 subnet-0bbb222 subnet-0ccc333
POD_SUBNETS=subnet-0ddd444 subnet-0eee555 subnet-0fff666
PUBLIC_ROUTE_TABLE_ID=rtb-0123456
POD_ROUTE_TABLE_ID=rtb-0789abc
INTERNET_GATEWAY_ID=igw-0abcdef
NAT_GATEWAY_ID=
NAT_EIP_ALLOCATION_ID=
```

**Verify the VPC was created:**

```bash
aws ec2 describe-vpcs \
  --region us-east-2 \
  --filters Name=tag:Name,Values=student1-vpc \
  --query 'Vpcs[].{Id:VpcId,Cidr:CidrBlock,State:State}' \
  --output table
```

---

## Step 2 — Generate the Cluster Config

The bootstrap script discovers your subnets by their EKS tags and renders a ready-to-use `eksctl` config file.

```bash
cd $HOME/eks-cluster-setup/eksctl

./02-eks/eks-training-bootstrap.sh student1 student1-vpc 1.36
```

You can pass the VPC ID directly instead of the name:
```bash
./02-eks/eks-training-bootstrap.sh student1 vpc-0abc1234567890def 1.36
```

**Review the generated config:**

```bash
cat 02-eks/cluster.generated.yaml
```

Check that these fields are correctly filled in (no placeholder strings):

- `metadata.name` → your cluster name
- `vpc.id` → your VPC ID (e.g. `vpc-0abc...`)
- `vpc.subnets.public` → 3 real subnet IDs

> **Stop here if you still see `CLUSTER_NAME`, `VPC_ID`, `AZ_1`, or `PUBLIC_SUBNET_1` as literal text.** Something went wrong with the substitution — re-check your VPC name or ID.

For the full eksctl schema reference:
```bash
less 02-eks/cluster.full-reference.yaml
# or check what your installed version supports:
eksctl utils schema
```

---

## Step 3 — Create the EKS Cluster

```bash
cd $HOME/eks-cluster-setup/eksctl

eksctl create cluster -f 02-eks/cluster.generated.yaml
```

⏱️ **This takes 15–20 minutes.** eksctl streams CloudFormation events to your terminal.

**What gets created:**

| Resource | Detail |
|---|---|
| EKS control plane | Managed by AWS (you pay for it, but don't manage it) |
| OIDC provider | Enables IAM Roles for Service Accounts (IRSA) |
| Managed node group | 2 × `t3.small` worker nodes |
| Core add-ons | `vpc-cni`, `coredns`, `kube-proxy`, `eks-pod-identity-agent`, `aws-ebs-csi-driver` |
| IAM roles | Cluster role + node role |

> **Expected final line:**
> ```
> ✓ EKS cluster "student1" in "us-east-2" region is ready
> ```

---

## Step 4 — Configure kubeconfig and Verify Access

```bash
cd $HOME/eks-cluster-setup/eksctl

./02-eks/post-create.sh student1 us-east-2
```

This script:
1. Updates your local `~/.kube/config` for this cluster
2. Prints cluster endpoint and OIDC issuer details
3. Runs `kubectl auth can-i get nodes` and `kubectl get nodes`

**Expected output:**
```
Updating kubeconfig for current caller...
Added new context arn:aws:eks:us-east-2:123456789012:cluster/student1 to ~/.kube/config

NAME                                          STATUS   ROLES    AGE   VERSION
ip-10-50-1-xxx.us-east-2.compute.internal    Ready    <none>   2m    v1.36.x
ip-10-50-2-xxx.us-east-2.compute.internal    Ready    <none>   2m    v1.36.x
```

### Grant access to another IAM user (optional)

```bash
./02-eks/post-create.sh student1 us-east-2 student1-admin
# or with a full ARN:
./02-eks/post-create.sh student1 us-east-2 arn:aws:iam::123456789012:role/trainer-admin
```

The added user must then run on their own machine:
```bash
aws eks update-kubeconfig --name student1 --region us-east-2
kubectl get nodes
```

### Set convenience variables

Export these now — they are used in most commands throughout the rest of the lab:

```bash
export CLUSTER_NAME=student1
export REGION=us-east-2
```

---

## Step 5 — Post-Creation Verification Checks

Run these to confirm the cluster is fully healthy before proceeding.

### Cluster status

```bash
eksctl get cluster --name $CLUSTER_NAME --region $REGION

aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --query "cluster.{Status:status,Version:version,UpgradePolicy:upgradePolicy.supportType}"
```

### Node group status

```bash
eksctl get nodegroup --cluster $CLUSTER_NAME --region $REGION
```

### Add-on status

```bash
eksctl get addon --cluster $CLUSTER_NAME --region $REGION
```

All add-ons should show `ACTIVE`.

### Kubernetes health

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get events -A --sort-by=.lastTimestamp
```

> If a pod is `CrashLoopBackOff` or `Pending`:
> ```bash
> kubectl describe pod <pod-name> -n <namespace>
> kubectl logs <pod-name> -n <namespace>
> ```

---

## Step 6 — Enable Custom Pod Networking

Custom networking tells the VPC CNI plugin to attach pod ENIs onto the **secondary CIDR** (`100.64.0.0/16`) pod subnets instead of the primary node subnets — giving you a much larger pod IP pool.

> **Why recycle nodes?** The `ENIConfig` is read by the VPC CNI when a node first joins the cluster. Nodes that already exist were created before the ENIConfig existed, so they will never pick it up. You must delete the existing nodes and let eksctl create fresh ones.

The process is: **enable custom networking → recycle nodes → verify**.

---

### Step 6a — Run the custom networking script

```bash
cd $HOME/eks-cluster-setup/eksctl

./03-custom-networking/enable-custom-networking.sh student1
```

**What the script does:**
1. Discovers pod subnets tagged `kubernetes.io/role/internal-elb=1` in your cluster VPC
2. Creates one `ENIConfig` CRD per Availability Zone pointing to the pod subnet + cluster security group
3. Sets `AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true` on the `aws-node` DaemonSet
4. Sets `ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone` so new nodes auto-select the right ENIConfig
5. Enables prefix delegation (`ENABLE_PREFIX_DELEGATION=true`) — boosts max pods per node significantly
6. Restarts the `aws-node` DaemonSet and waits for rollout to complete

**Verify ENIConfigs were created (one per AZ):**
```bash
kubectl get eniconfig
```

```
NAME          AGE
us-east-2a    30s
us-east-2b    30s
us-east-2c    30s
```

---

### Step 6b — Delete the existing node group

The current `workers` node group must be deleted so fresh nodes can be created to pick up the ENIConfig.

```bash
export CLUSTER_NAME=student1
export REGION=us-east-2

eksctl delete nodegroup \
  --cluster $CLUSTER_NAME \
  --region  $REGION \
  --name    workers \
  --wait
```

⏱️ **This takes ~5 minutes.** eksctl drains and terminates all nodes, then deletes the CloudFormation stack for the node group.

**Verify the node group is gone:**
```bash
eksctl get nodegroup --cluster $CLUSTER_NAME --region $REGION
# Should return empty / no resources found
```

---

### Step 6c — Create a new node group

```bash
eksctl create nodegroup \
  --cluster      $CLUSTER_NAME \
  --region       $REGION \
  --name         workers \
  --node-type    t3.small \
  --nodes        2 \
  --nodes-min    2 \
  --nodes-max    3 \
  --managed
```

⏱️ **This takes ~5 minutes.**

**Verify new nodes are Ready:**
```bash
kubectl get nodes -o wide
```

```
NAME                                          STATUS   ROLES    AGE   VERSION   INTERNAL-IP
ip-10-50-1-xxx.us-east-2.compute.internal    Ready    <none>   2m    v1.36.x   10.50.1.xxx
ip-10-50-2-xxx.us-east-2.compute.internal    Ready    <none>   2m    v1.36.x   10.50.2.xxx
```

> Node IPs remain in the **primary CIDR** (`10.50.x.x`) — nodes still live in the public subnets. The change is where **pod** IPs come from, which you verify in Step 6d.

---

### Step 6d — Verify pod capacity and networking

**Check max pod capacity per node:**
```bash
kubectl get node -o custom-columns=NODE:.metadata.name,PODS:.status.capacity.pods
```

> With prefix delegation on `t3.small`, capacity jumps from ~11 pods to **110+ pods** per node.

**Spin up a test pod and check its IP:**
```bash
kubectl run nettest --image=public.ecr.aws/nginx/nginx:stable --restart=Never
kubectl wait pod/nettest --for=condition=Ready --timeout=60s
kubectl get pod nettest -o wide
```

Expected output — the `IP` column must be in the `100.64.x.x` range:
```
NAME      READY   STATUS    IP            NODE
nettest   1/1     Running   100.64.1.23   ip-10-50-1-xxx.us-east-2.compute.internal
```

> - **Pod IP** `100.64.x.x` → secondary CIDR (pod subnet via ENIConfig) ✅
> - **Node IP** `10.50.x.x` → primary CIDR (public subnet, unchanged) ✅

**Clean up the test pod:**
```bash
kubectl delete pod nettest
```

---




## Step 7 — Install Add-ons

### 7a. EBS CSI Driver

The EBS CSI driver was already installed as an EKS-managed add-on in Step 3. Verify it is active:

```bash
eksctl get addon --cluster $CLUSTER_NAME --region $REGION | grep ebs
```

If you need to install or update it manually:

```bash
cd $HOME/eks-cluster-setup/eksctl
./04-addons/install-ebs-csi.sh $CLUSTER_NAME $REGION
```

This script:
- Creates an IAM role `AmazonEKS_EBS_CSI_DriverRole_student1` with IRSA
- Installs or updates the `aws-ebs-csi-driver` EKS add-on

### 7b. AWS Load Balancer Controller

Watches Kubernetes `Ingress` and `Service` resources to automatically provision ALBs and NLBs in your AWS account.

> **Prerequisite:** `helm` must be installed (`helm version`).

```bash
cd $HOME/eks-cluster-setup/eksctl
./04-addons/install-aws-load-balancer-controller.sh $CLUSTER_NAME $REGION
```

**What the script does:**
1. Downloads the official IAM policy JSON from GitHub
2. Creates IAM policy `AWSLoadBalancerControllerIAMPolicy-student1`
3. Creates an IAM service account via `eksctl` (uses IRSA)
4. Installs the controller via Helm (`eks/aws-load-balancer-controller`)
5. Waits for the controller deployment to become ready

**Verify:**
```bash
kubectl get deployment aws-load-balancer-controller -n kube-system
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=20
```

### 7c. Metrics Server

Enables `kubectl top nodes` and `kubectl top pods` for real-time CPU/memory usage.

```bash
cd $HOME/eks-cluster-setup/eksctl
./04-addons/install-metrics-server.sh
```

**Verify:**
```bash
kubectl top nodes
kubectl top pods -A
```

> Allow up to 60 seconds after installation before `kubectl top` returns data.

---

## Step 8 — Deploy a Sample Application

Deploy a 2-replica nginx workload and expose it publicly through an internet-facing ALB.

### Deploy nginx Deployment and Service

```bash
cd $HOME/eks-cluster-setup/eksctl

kubectl apply -f 05-applications/nginx.yaml
```

```bash
# Verify pods are running
kubectl get pods -l app=nginx

# Verify ClusterIP service
kubectl get svc nginx
```

### Create the Ingress (ALB)

> **Prerequisite:** AWS Load Balancer Controller must be installed (Step 7b).

```bash
kubectl apply -f 05-applications/ingress.yaml
```

Watch the ALB being provisioned (takes 2–3 minutes):
```bash
kubectl get ingress nginx --watch
```

Once the `ADDRESS` column is populated with a DNS name:
```bash
kubectl get ingress nginx
# Test it:
curl http://<ALB-DNS-NAME>
```

> **Expected response:** nginx welcome page HTML.

**How it works:** The `ingress.yaml` uses annotations:
- `alb.ingress.kubernetes.io/scheme: internet-facing` → creates a public ALB in your public subnets
- `alb.ingress.kubernetes.io/target-type: ip` → routes traffic directly to pod IPs (requires VPC CNI)

---

## Step 9 — Useful Day-2 Commands

### Refresh kubeconfig
```bash
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION
```

### Scale the node group
```bash
eksctl scale nodegroup \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --name workers \
  --nodes 3
```

### Check CloudFormation stacks
```bash
eksctl utils describe-stacks --cluster $CLUSTER_NAME --region $REGION
```

### Check access entries
```bash
eksctl get accessentry --cluster $CLUSTER_NAME --region $REGION -o yaml
```

### Check IAM service accounts
```bash
eksctl get iamserviceaccount --cluster $CLUSTER_NAME --region $REGION
```

### Dry-run cluster delete (safe to run — makes no changes)
```bash
eksctl delete cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --dry-run
```

---

## Step 10 — Cleanup (End of Lab)

> **Always delete in this order** to avoid orphaned ALBs blocking VPC deletion.

### 1. Delete Kubernetes Ingress resources first

```bash
cd $HOME/eks-cluster-setup/eksctl

kubectl delete -f 05-applications/ingress.yaml
```

Wait for the ALB to be fully deprovisioned before moving on (~2 minutes):
```bash
kubectl get ingress nginx --watch
# Wait until the ingress disappears from the list
```

### 2. Find your VPC ID (if not already saved)

```bash
VPC_ID=$(aws ec2 describe-vpcs \
  --region us-east-2 \
  --filters Name=tag:Name,Values=student1-vpc \
  --query 'Vpcs[0].VpcId' \
  --output text)
echo $VPC_ID
```

### 3. Run the all-in-one cleanup

```bash
cd $HOME/eks-cluster-setup/eksctl

./cleanup/cleanup-all.sh student1 us-east-2 $VPC_ID
```

This runs `delete-cluster.sh` (waits ~10 minutes) then `delete-vpc.sh`.

Or step-by-step:

```bash
cd $HOME/eks-cluster-setup/eksctl

# Delete EKS cluster first (waits until complete)
./02-eks/delete-cluster.sh student1

# Then delete the VPC
./01-network/delete-vpc.sh us-east-2 $VPC_ID
# or by name:
./01-network/delete-vpc.sh us-east-2 student1-vpc
```

### 4. Verify everything is deleted

```bash
# Should return empty
eksctl get cluster --region us-east-2

# Should return None
aws ec2 describe-vpcs \
  --region us-east-2 \
  --filters Name=tag:Name,Values=student1-vpc \
  --query 'Vpcs[].VpcId' \
  --output text
```

---

## Troubleshooting

### `eksctl create cluster` fails

```bash
# Check CloudFormation for the specific error
aws cloudformation describe-stack-events \
  --region us-east-2 \
  --stack-name eksctl-student1-cluster \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
  --output table
```

### Nodes stuck — not reaching `Ready`

```bash
kubectl describe node <node-name>
kubectl get events --sort-by=.lastTimestamp -A
```

### Pods stuck in `Pending`

Common causes and fixes:

| Cause | Fix |
|---|---|
| Node capacity exhausted | `eksctl scale nodegroup ... --nodes 3` |
| No ENIConfig for AZ | Re-run `enable-custom-networking.sh` |
| Image pull failure | Check node has internet access (public subnet + IGW) |

```bash
kubectl describe pod <pod-name>
```

### `kubectl` returns "Unauthorized"

```bash
# Refresh kubeconfig
aws eks update-kubeconfig --name student1 --region us-east-2

# Confirm your identity
aws sts get-caller-identity

# Check you have an access entry
eksctl get accessentry --cluster student1 --region us-east-2
```

### ALB not provisioned after applying Ingress

```bash
# Check controller logs for errors
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=50

# Verify public subnets have the required EKS tag
aws ec2 describe-subnets \
  --region us-east-2 \
  --filters Name=vpc-id,Values=$VPC_ID \
            Name=tag:kubernetes.io/role/elb,Values=1 \
  --query 'Subnets[].{Id:SubnetId,AZ:AvailabilityZone}' \
  --output table
```

---

## File Reference

| File | Purpose |
|---|---|
| `01-network/create-vpc.sh` | Creates VPC, subnets, IGW, and route tables |
| `01-network/delete-vpc.sh` | Deletes the VPC and all its resources |
| `02-eks/eks-training-bootstrap.sh` | Generates `cluster.generated.yaml` from template |
| `02-eks/cluster.yaml` | Template cluster config (do not edit directly) |
| `02-eks/cluster.generated.yaml` | Generated config (created by bootstrap script) |
| `02-eks/cluster.full-reference.yaml` | Full eksctl schema reference (read-only) |
| `02-eks/post-create.sh` | Configures kubeconfig + grants IAM access entries |
| `02-eks/delete-cluster.sh` | Deletes the EKS cluster |
| `03-custom-networking/enable-custom-networking.sh` | Sets up VPC CNI custom networking with ENIConfigs |
| `03-custom-networking/eniconfig.yaml` | ENIConfig template (applied by the script above) |
| `04-addons/install-ebs-csi.sh` | Installs EBS CSI driver with IRSA |
| `04-addons/install-aws-load-balancer-controller.sh` | Installs AWS LB Controller via Helm |
| `04-addons/install-metrics-server.sh` | Installs Kubernetes Metrics Server |
| `05-applications/nginx.yaml` | Sample nginx Deployment + ClusterIP Service |
| `05-applications/ingress.yaml` | Internet-facing ALB Ingress for nginx |
| `cleanup/cleanup-all.sh` | Deletes cluster + VPC in one command |
| `scripts/install-eksctl.sh` | Installs eksctl binary |
