# Cluster Guide — Build Your Own EKS Cluster

This guide walks you through creating **your own, fully isolated** EKS
cluster and supporting AWS infrastructure using the Terraform code in this
repository, and explains how to spin up **multiple clusters** from the same
code by changing only variables — no code changes required.

Each cluster you create is completely separate from every other cluster: its
own VPC, its own EKS control plane, its own node group, and its own Terraform
state (via a dedicated Terraform workspace).

---

## 0. How this is organized (read this first)

The Terraform code is split into small modules that are composed together:

```
terraform/02-clusters/                  <- root module YOU run (per-cluster entrypoint)
  └── modules/cluster/               <- wires everything together for one cluster
        ├── modules/networking       <- VPC, subnets, routing, security groups
        ├── modules/iam              <- IAM roles for the cluster & worker nodes
        ├── modules/eks              <- the EKS control plane + node group(s)
        ├── modules/addons           <- VPC CNI, CoreDNS, kube-proxy, EBS CSI, metrics-server, ALB controller
        ├── modules/storage          <- default StorageClass (gp3 EBS volumes)
        └── modules/monitoring       <- optional CloudWatch log group for the cluster
```

You never edit these modules. You only supply a **cluster name** (plus
optional variables), and the root module looks up settings (instance type,
node count, CIDR ranges, etc.) from a shared config map
(`clusters.auto.tfvars.json`) so the same code scales from 1 cluster to many
without any code changes.

---

## 1. Prerequisites

Install these once:

- **AWS CLI** — configured with credentials for the target AWS account
  (`aws sts get-caller-identity` should return your identity).
- **Terraform** >= 1.8 — the tool that reads the `.tf` files and creates AWS
  resources on your behalf.
- **kubectl** — the Kubernetes CLI you'll use to talk to your cluster once it
  exists.
- **helm** — used internally by the `addons` module to install things like
  the metrics-server; useful for inspecting installed charts (`helm list -A`).

Install scripts for all of these are in `00-prerequisites/` if you
need them.

**What's happening:** Terraform is the tool that actually creates your VPC,
EKS cluster, and nodes in AWS by calling the AWS API. The AWS CLI provides
the credentials Terraform uses to authenticate those API calls.

---

## 2. Required variables for a single cluster

The `modules/cluster` module (and the `clusters/` root module that wraps it)
takes these key inputs:

| Variable | Required? | What it controls |
|---|---|---|
| `cluster_name` | **Required** | Unique identifier for this cluster; used as the Terraform workspace name and to prefix every AWS resource name/tag |
| `environment` | Optional (default `dev`) | Environment label tag (`dev`, `staging`, `prod`, ...) |
| `owner` | Optional | Owner/team tag |
| `region` | Optional (default `us-east-2`) | AWS region to deploy into |
| `vpc_cidr` | Optional | Private IP range for this cluster's VPC (must not overlap other clusters if they are ever peered) |
| `pod_cidr` | Optional | Secondary CIDR for custom pod networking (more IPs for pods) |
| `instance_type` | Optional (default `t3.medium`) | EC2 instance type for worker nodes |
| `node_count` / `node_min_size` / `node_max_size` | Optional | How many worker nodes this cluster gets |
| `enable_ebs_csi`, `enable_metrics_server`, `enable_alb_controller` | Optional | Which add-ons get installed |
| `enable_private_subnets`, `enable_nat_gateway` | Optional | Whether this cluster gets private subnets + NAT (costs more, closer to production) |

Only `cluster_name` has no default — everything else has a sane default so a
minimal cluster only needs one variable.

---

## 3. Creating a single cluster directly (module-only, no workspaces)

For the simplest possible case — one cluster, one set of variables — you can
call the module directly, as shown in `terraform/examples/single-cluster/main.tf`:

```hcl
module "cluster" {
  source = "../../01-modules/cluster"

  cluster_name = "dev01"
  environment  = "dev"
  owner        = "platform-team"

  instance_type = "t3.medium"
  node_count    = 3
}
```

```bash
cd terraform/examples/single-cluster
terraform init
terraform apply
```

**What this does:** initializes providers and applies the `cluster` module
with the variables you supplied, creating one complete, isolated EKS
environment. This pattern is ideal when you truly only need one cluster and
don't need the multi-cluster workspace machinery described below.

---

## 4. Creating multiple clusters from the same code

To run several clusters side by side (each isolated, each with its own
state), use the `terraform/02-clusters/` root module together with **Terraform
workspaces** — one workspace per cluster.

### 4.1 Register the cluster's configuration

Open `terraform/02-clusters/clusters.auto.tfvars.json` and add an entry keyed by
your chosen `cluster_name`:

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

**What this does:** you're not editing Terraform code — you're just adding a
new key to a JSON map. Each key is a `cluster_name`; each value is the full
set of settings for that cluster. Add as many keys as you need clusters.

### 4.2 Initialize Terraform (one-time)

```bash
cd terraform/02-clusters
terraform init
```

**What this does:**
- Downloads the AWS, Kubernetes, Helm, and TLS provider plugins.
- Sets up the local backend, where Terraform's **state** (a record of what
  resources exist and their IDs) is stored.

### 4.3 Create a Terraform workspace per cluster

```bash
terraform workspace new dev01     # or: terraform workspace select dev01
```

**What this does:** a Terraform **workspace** gives you an isolated state
file (stored under `terraform.tfstate.d/dev01/`). This is the mechanism that
keeps each cluster's tracked state completely separate, even though every
cluster is created from the exact same `.tf` code. When you run `terraform
apply`, Terraform only looks at the *active* workspace's state.

### 4.4 Apply

```bash
terraform apply -var="cluster_name=dev01"
```

Terraform resolves `local.cluster_key` to `dev01` (from `-var` or, if
omitted, from the active workspace name), looks up its config in
`var.clusters["dev01"]`, and passes it into the `cluster` module — which then
provisions networking, IAM, the EKS control plane, node group, add-ons,
storage class, and monitoring, exactly as described in section 5 below.

### 4.5 The easy way: one script does 4.2–4.4 for you

```bash
cd terraform
./automation/create-one.sh dev01
```

To create **every** cluster listed in `clusters.auto.tfvars.json` in
parallel:

```bash
./automation/create-all.sh
```

**What this does:** reads all keys from `clusters.auto.tfvars.json` and runs
`create-one.sh <cluster_name>` for each one in the background, so many
clusters can come up concurrently.

---

## 5. What actually gets created (step by step)

Whichever path you used above (section 3 or 4), applying the `cluster`
module creates, in order:

1. **networking module**
   - A VPC with your configured CIDR block.
   - Public subnets across multiple Availability Zones (and private subnets
     + a NAT gateway if enabled) — subnets are where your EC2/EKS resources
     actually live.
   - An Internet Gateway and route tables so subnets can reach the internet
     (needed to pull container images, etc.).
   - A security group used by the EKS cluster's network interfaces.
2. **iam module**
   - An IAM role for the EKS control plane (lets AWS manage the cluster on
     your behalf).
   - An IAM role + instance profile for worker nodes (lets EC2 instances
     join the cluster and pull images from ECR).
3. **eks module**
   - The **EKS control plane** (`aws_eks_cluster`) — the managed Kubernetes
     API server, etcd, and scheduler that AWS runs for you.
   - An **OIDC identity provider** for the cluster, which lets Kubernetes
     service accounts assume IAM roles (used later by the EBS CSI driver and
     ALB controller add-ons).
   - An **access entry** granting your AWS identity cluster-admin so you can
     run `kubectl` against it immediately.
   - A **managed node group** — the actual EC2 worker nodes that join the
     cluster and run your pods (count/size come from your config).
4. **addons module**
   - Core EKS add-ons: `vpc-cni` (pod networking), `coredns` (DNS),
     `kube-proxy` (service routing).
   - Optionally the **EBS CSI driver** (provisions EBS volumes for
     persistent storage), **metrics-server** (powers `kubectl top` and
     autoscaling), and the **AWS Load Balancer Controller** (creates
     ALBs/NLBs from Kubernetes Ingress/Service objects).
5. **storage module** — a default `gp3` StorageClass so
   `PersistentVolumeClaim`s work out of the box.
6. **monitoring module** (if enabled) — a CloudWatch Log Group for cluster
   control-plane logs.

This takes roughly **15–20 minutes**, mostly waiting for AWS to provision the
EKS control plane and for worker nodes to boot and join the cluster.

---

## 6. Access your cluster

```bash
./automation/generate-kubeconfig.sh dev01
export KUBECONFIG=$(pwd)/kubeconfig-dev01
kubectl get nodes
```

**What this does:**
- `generate-kubeconfig.sh` runs `aws eks update-kubeconfig` under the hood,
  writing a kubeconfig file that tells `kubectl` your cluster's API endpoint
  and how to authenticate (using your AWS CLI credentials + an `aws eks
  get-token` exec plugin — no static passwords involved).
- `export KUBECONFIG=...` points `kubectl` at that file instead of the
  default `~/.kube/config`, so multiple clusters' kubeconfigs never collide.
- `kubectl get nodes` confirms your worker nodes have joined the cluster and
  are `Ready`.

---

## 7. Check cluster health

```bash
./automation/health-check.sh dev01
```

**What this does:** runs a set of sanity checks (cluster status, node
readiness, core add-on pod status, etc.) so you can quickly confirm
everything came up correctly without manually running several `kubectl`
commands.

---

## 8. Deploy something and try it out

```bash
kubectl apply -f ../eksctl/05-applications/nginx.yaml
kubectl apply -f ../eksctl/05-applications/ingress.yaml
kubectl get pods,svc,ingress
```

**What this does:** schedules a pod onto your worker nodes and (if the ALB
controller add-on is enabled) provisions a real AWS Application Load
Balancer that routes traffic to it — a good end-to-end test that networking,
IAM, and add-ons are all wired correctly.

---

## 9. Destroy a cluster

```bash
./automation/destroy-one.sh dev01
```

**What this does:** selects the `dev01` workspace and runs `terraform
destroy`, which deletes every AWS resource Terraform created for that
cluster (node group, control plane, IAM roles, VPC, etc.) in the correct
dependency order, then removes the workspace. Nothing belonging to other
clusters is touched.

To tear down every cluster currently deployed:

```bash
./automation/destroy-all.sh
```

**Cost tip:** the EKS control plane and running EC2 nodes are the two
biggest costs. Destroying clusters when not in use is expected practice —
recreating later only takes the ~15–20 minutes from section 5.

---

## 10. Rules of the road

- **Never create AWS resources manually in the console.** Everything must go
  through `terraform apply` (via the scripts above) so it stays tracked in
  state and can be cleanly destroyed.
- **One workspace per cluster.** Don't apply changes for `dev01` while a
  different cluster's workspace is selected.
- **If something looks wrong**, run `./automation/health-check.sh <cluster_name>`
  and check `docs/Troubleshooting.md` before digging further.
- Each cluster is fully isolated: separate VPC, separate EKS control plane,
  separate Terraform state — nothing done to one cluster can affect another.
