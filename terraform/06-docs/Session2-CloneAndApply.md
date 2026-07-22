# Session Guide 2 — Clone the Repo & Create Your Cluster (Student, Jump Box)

**Audience:** Students, on their own jump box (Terraform, AWS CLI, kubectl,
helm already installed per `00-prerequisites/`).
**Goal:** Clone the repo, set a unique cluster name, and run `terraform
apply` to create one fully isolated EKS cluster + infrastructure.

---

## 1. Confirm prerequisites on your jump box

```bash
terraform -version   # >= 1.8
aws --version
kubectl version --client
aws sts get-caller-identity   # confirms your AWS credentials work
```

If any of these fail, run the install scripts in `00-prerequisites/`
first (ask your trainer for the jump box's install instructions if this
wasn't done already).

---

## 2. Clone the repository

```bash
git clone <repo-url> eks-platform
cd eks-platform/terraform/examples/single-cluster
```

**What this does:** downloads a copy of the Terraform modules onto your jump
box. You will only ever work inside `examples/single-cluster/` — everything
under `../../01-modules/` is shared code you don't need to edit.

---

## 3. Set your unique cluster name

Open `main.tf` in this directory and change `cluster_name` to something
unique to you (e.g. your first name + a number, or your assigned student
ID):

```hcl
module "cluster" {
  source = "../../01-modules/cluster"

  cluster_name = "alice01"     # <-- change this to your own unique name
  environment  = "dev"
  owner        = "alice"

  instance_type = "t3.medium"
  node_count    = 3
}
```

**Why this matters:** `cluster_name` prefixes every AWS resource this
creates (VPC, IAM roles, EKS cluster name, etc.) and is used for tagging. If
two students in the same AWS account pick the same name, their resources
will collide. Everything else in the file can be left at its default.

Optional tweaks you can make here (all optional, defaults shown):

| Variable | Default | Notes |
|---|---|---|
| `instance_type` | `t3.medium` | Larger if your labs need more CPU/memory |
| `node_count` | `3` | Number of worker nodes |
| `enable_ebs_csi` | `true` | Needed for `PersistentVolumeClaim`s |
| `enable_metrics_server` | `true` | Needed for `kubectl top` |
| `enable_alb_controller` | `false` | Turn on if your labs use Ingress/ALB |

---

## 4. Initialize Terraform

```bash
terraform init
```

**What this does:** downloads the AWS/Kubernetes/Helm/TLS provider plugins
and sets up your **local** Terraform state file (`terraform.tfstate`) in
this directory — this is where Terraform will track everything it creates
for you.

---

## 5. Preview the plan (recommended)

```bash
terraform plan
```

**What this does:** shows every resource Terraform is about to create,
without actually creating anything. Good habit to review before `apply`,
especially the first time.

---

## 6. Apply — create your cluster

```bash
terraform apply
```

Terraform will show the same plan and prompt:

```
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value:
```

Type `yes` and press Enter.

**What this does:** creates, in order, your VPC/subnets/security groups,
IAM roles, the EKS control plane, the OIDC provider, the managed node
group, core + optional add-ons, and the default storage class — everything
described in Guide 1. This takes **roughly 15–20 minutes**; most of the wait
is AWS provisioning the EKS control plane and nodes booting/joining.

When it finishes, Terraform prints your outputs, including:

```
kubeconfig_command = "aws eks update-kubeconfig --name eks-alice01-cluster --region us-east-2 --alias alice01"
```

---

## 7. Next step

Continue to **Guide 3** to generate your kubeconfig, access the cluster,
and deploy an application.
