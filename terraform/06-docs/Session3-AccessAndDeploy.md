# Session Guide 3 — Access Your Cluster & Deploy Applications (Student)

**Audience:** Students, right after completing Guide 2 (`terraform apply`
succeeded).
**Goal:** Generate a kubeconfig, verify the cluster is healthy, and deploy a
sample application.

---

## 1. Generate your kubeconfig

Use the `kubeconfig_command` output printed at the end of your `terraform
apply` (or re-print it any time with `terraform output kubeconfig_command`):

```bash
aws eks update-kubeconfig \
  --name eks-<your-cluster_name>-cluster \
  --region us-east-2 \
  --alias <your-cluster_name>
```

**What this does:** writes/updates `~/.kube/config` with a new context for
your cluster, configured to authenticate using your AWS CLI credentials via
an `aws eks get-token` exec plugin — no static passwords or certificates to
manage yourself.

If you prefer to keep it isolated from any other kubeconfig on the jump box:

```bash
aws eks update-kubeconfig \
  --name eks-<your-cluster_name>-cluster \
  --region us-east-2 \
  --alias <your-cluster_name> \
  --kubeconfig ./kubeconfig-<your-cluster_name>

export KUBECONFIG=$(pwd)/kubeconfig-<your-cluster_name>
```

---

## 2. Verify the cluster is healthy

```bash
kubectl get nodes -o wide
```

You should see your worker nodes (3 by default) in `Ready` status. If not
yet ready, wait a minute and re-run — nodes can take a short time to
register after the control plane reports active.

```bash
kubectl get pods -n kube-system
```

Confirm core add-on pods (`aws-node` for VPC CNI, `coredns`, `kube-proxy`,
and `ebs-csi-*` if enabled) are all `Running`.

```bash
kubectl get sc
```

Confirm the default `gp3` StorageClass exists (created by the `storage`
module).

---

## 3. Deploy a sample application

```bash
kubectl apply -f ../../../eksctl/05-applications/nginx.yaml
kubectl get pods -o wide
kubectl get svc
```

**What this does:** schedules an `nginx` pod onto one of your worker nodes
and exposes it via a Kubernetes Service — confirms pod scheduling, image
pulls, and in-cluster networking are all working.

If the AWS Load Balancer Controller add-on is enabled for your cluster
(`enable_alb_controller = true`), you can also try the Ingress example:

```bash
kubectl apply -f ../../../eksctl/05-applications/ingress.yaml
kubectl get ingress
```

**What this does:** the ALB controller watches for `Ingress` objects and
provisions a real AWS Application Load Balancer, wiring it up to route
traffic to your Service/pods. It can take a minute or two for the ALB's
`ADDRESS` to populate — check with `kubectl get ingress -w`.

---

## 4. Try persistent storage (optional)

If you want to confirm the EBS CSI driver works end-to-end, create a
`PersistentVolumeClaim` against the default StorageClass and watch it bind:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: demo-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 2Gi
EOF

kubectl get pvc demo-pvc -w
```

A `PVC` stuck in `Pending` usually means `enable_ebs_csi` was left `false`
for your cluster — see `docs/Troubleshooting.md`.

---

## 5. Clean up sample workloads (recommended before destroying)

```bash
kubectl delete -f ../../../eksctl/05-applications/ingress.yaml --ignore-not-found
kubectl delete -f ../../../eksctl/05-applications/nginx.yaml --ignore-not-found
kubectl delete pvc demo-pvc --ignore-not-found
```

**Why:** any `Service type=LoadBalancer` or `Ingress` you created causes AWS
to provision an ELB/ALB *outside* of Terraform's tracking. If you leave
these running, `terraform destroy` (Guide 4) can hang or fail waiting for
the VPC's ENIs to be released. Deleting Kubernetes-created load balancers
first avoids that.

---

## 6. Next step

Continue to **Guide 4** to destroy your cluster when you're done for the
session.
