# Session Guide 5 — Trainer: Create/Destroy Multiple Clusters at Once

**Audience:** Trainer only (not distributed to students).
**Goal:** Stand up (and tear down) several clusters in one shot — e.g. to
pre-provision environments for a whole batch, or to run a demo showing
several clusters side by side.

This uses the `terraform/02-clusters/` root module + Terraform **workspaces**
(one workspace per cluster), driven by the `automation/create-all.sh` /
`automation/destroy-all.sh` scripts — students do **not** need this; they
use `examples/single-cluster` (Guides 2–4).

---

## 1. Register every cluster you want to create

Edit `terraform/02-clusters/clusters.auto.tfvars.json` and add one entry per
cluster, keyed by a unique `cluster_name`:

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
    },
    "dev02": {
      "kubernetes_version": "1.31",
      "instance_type": "t3.medium",
      "capacity_type": "ON_DEMAND",
      "node_count": 3,
      "node_min_size": 1,
      "node_max_size": 5,
      "enable_managed_node_group": true,
      "enable_unmanaged_node_group": false,
      "vpc_cidr": "10.1.0.0/16",
      "enable_custom_pod_networking": true,
      "pod_cidr": "100.65.0.0/16",
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

**Important:** give each cluster a **different `vpc_cidr`/`pod_cidr`** to
avoid overlap in case VPCs are ever peered or shared-transit-gateway'd
together later.

---

## 2. Create every cluster at once

```bash
cd terraform
./automation/create-all.sh
```

**What this does:**
1. Reads every key from `clusters/clusters.auto.tfvars.json` via `jq`.
2. For each key, runs `automation/create-one.sh <cluster_name>` **in the
   background in parallel**, which:
   - `cd`s into `terraform/02-clusters`.
   - Runs `terraform init` (once; safe if already initialized).
   - Creates (or selects, if it already exists) a Terraform **workspace**
     named after the cluster — this gives each cluster its own isolated
     state file under `clusters/terraform.tfstate.d/<cluster_name>/`.
   - Runs `terraform apply -auto-approve -var="cluster_name=<name>"`.
3. Waits for all background jobs to finish.

Because AWS API calls for independent clusters don't conflict, running them
in parallel is safe and significantly faster than creating them one at a
time — expect the whole batch to complete in roughly the same ~15–20
minutes as a single cluster, not N × 15–20 minutes.

---

## 3. Check on progress / verify

```bash
cd terraform/02-clusters
terraform workspace list
```

Shows every workspace (cluster) currently tracked. To check a specific
cluster's health:

```bash
cd ../
./automation/health-check.sh dev01
./automation/health-check.sh dev02
```

Rough cost/resource summary across all clusters in the account:

```bash
./scripts/cost-summary.sh us-east-2
```

---

## 4. Generate kubeconfigs for all students in bulk (optional)

```bash
for c in $(jq -r '.clusters | keys[]' terraform/02-clusters/clusters.auto.tfvars.json); do
  ./automation/generate-kubeconfig.sh "$c"
done
```

Distribute each `kubeconfig-<cluster_name>` file to the corresponding
student, or have them generate their own per Guide 3 if they have AWS
credentials on their jump box.

---

## 5. Destroy every cluster at once

```bash
cd terraform
./automation/destroy-all.sh
```

**What this does:**
1. `cd`s into `terraform/02-clusters` and lists every existing Terraform
   workspace (excluding `default`).
2. For each workspace found, runs `automation/destroy-one.sh
   <cluster_name>` **sequentially**, which:
   - Selects that cluster's workspace.
   - Runs `terraform destroy -auto-approve -var="cluster_name=<name>"`.
   - Switches back to the `default` workspace and deletes the now-empty
     workspace.

**Before running this:** make sure students have cleaned up any
`Service type=LoadBalancer` / `Ingress` objects in their clusters (Guide 4,
step 1) — otherwise individual destroys may hang on ENI/ELB cleanup. You can
destroy sequentially and just re-run the script if one cluster gets stuck;
it will skip already-destroyed workspaces.

---

## 6. Destroying a single cluster from the batch (without affecting others)

```bash
cd terraform
./automation/destroy-one.sh dev02
```

This only touches the `dev02` workspace/state — every other cluster is
untouched.

---

## 7. End-of-batch checklist

- [ ] All students confirmed done / kubeconfigs no longer needed.
- [ ] `./automation/destroy-all.sh` completed with no errors.
- [ ] `terraform workspace list` (in `clusters/`) shows only `default`.
- [ ] `./scripts/cost-summary.sh us-east-2` shows no remaining EKS clusters,
      running instances, or NAT gateways tagged for this platform.
- [ ] Remove/rotate any generated `kubeconfig-*` files containing
      cluster-specific access if they're no longer needed.
