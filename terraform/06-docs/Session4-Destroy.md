# Session Guide 4 — Destroy Your Cluster (Student)

**Audience:** Students, at the end of a session/day.
**Goal:** Cleanly tear down every AWS resource created in Guides 2–3, to
avoid unnecessary cost.

---

## 1. Delete Kubernetes-created load balancers first (if any)

If you deployed the Ingress/ALB example or any `Service type=LoadBalancer`
in Guide 3 and haven't already removed it:

```bash
kubectl delete -f ../../../eksctl/05-applications/ingress.yaml --ignore-not-found
kubectl delete -f ../../../eksctl/05-applications/nginx.yaml --ignore-not-found
```

**Why this matters:** the AWS Load Balancer Controller and any
`type=LoadBalancer` Services create real ALBs/NLBs and ENIs that Terraform
does **not** manage directly. If they still exist when you run `terraform
destroy`, deletion of the VPC/subnets can hang or fail because AWS won't let
you delete a subnet with active ENIs in it.

---

## 2. Run terraform destroy

From the same directory you ran `apply` in (`examples/single-cluster`):

```bash
cd eks-platform/terraform/examples/single-cluster
terraform destroy
```

Review the list of resources Terraform prints, then confirm:

```
Do you really want to destroy all resources?
  Enter a value: yes
```

**What this does:** reads your local state file, works out the correct
dependency order (reverse of creation — add-ons first, then node group,
then EKS control plane, then IAM roles, then networking last), and deletes
every resource it created. Your state file is updated to reflect that
nothing remains.

This typically takes **10–15 minutes**.

---

## 3. Confirm everything is gone

```bash
aws eks list-clusters --region us-east-2
aws ec2 describe-instances --region us-east-2 \
  --filters "Name=tag:Cluster,Values=<your-cluster_name>" "Name=instance-state-name,Values=running"
```

Both should return empty/no results for your `cluster_name`.

---

## 4. If destroy gets stuck

- **Hangs deleting a subnet/VPC:** you likely still have a
  Kubernetes-created ELB/ENI. Check the AWS Console (EC2 → Load Balancers,
  EC2 → Network Interfaces) filtered by your VPC ID, delete manually, then
  re-run `terraform destroy`.
- **"resource not found" errors:** safe to ignore — it means AWS already
  removed something Terraform is also trying to delete (e.g. eventual
  consistency). Re-run `terraform destroy` again; it will skip resources
  that no longer exist.
- Full list of common issues: `docs/Troubleshooting.md`.

---

## 5. Recreating later

Nothing is deleted from your local `main.tf` — to stand the same cluster
back up, just repeat Guide 2 (`terraform apply`) from this same directory.
Since your local state file is now empty, Terraform will create everything
fresh again (~15–20 minutes).
