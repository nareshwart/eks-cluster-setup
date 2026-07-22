# Troubleshooting

**`terraform workspace select` fails with "workspace does not exist"**
Run `create-one.sh <cluster_name>` which creates the workspace automatically, or
`terraform workspace new <cluster_name>` manually.

**`kubectl get nodes` shows no nodes / nodes NotReady**
- Confirm the managed node group status: `aws eks describe-nodegroup --cluster-name eks-<cluster_name>-cluster --nodegroup-name eks-<cluster_name>-cluster-managed-ng`.
- Check that `vpc-cni` addon is `ACTIVE`: `aws eks describe-addon --cluster-name <cluster> --addon-name vpc-cni`.

**EBS volumes stuck `Pending`**
Ensure `enable_ebs_csi = true` for the cluster and that the `gp3` StorageClass
exists (`kubectl get sc`).

**`terraform destroy` hangs on ALB/NAT/ENI deletion**
Kubernetes-created ELBs/ENIs (from LoadBalancer services or the ALB
controller) must be deleted before the VPC can be destroyed. Delete any
`Service type=LoadBalancer` / `Ingress` objects first, then re-run destroy.

**Access denied running `kubectl` after apply**
The IAM identity that ran `terraform apply` is auto-granted cluster-admin via
an EKS access entry. If you're using a different identity, add an access
entry for it, or re-run apply with the original identity.
