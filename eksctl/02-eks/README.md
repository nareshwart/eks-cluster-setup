# 02-eks

Generates and creates an EKS cluster with `eksctl`.

1. Create the VPC first:

```bash
./01-network/create-vpc.sh us-east-2 student1 10.50.0.0/16
```

2. Generate an eksctl config:

```bash
./02-eks/eks-training-bootstrap.sh student1 student1-vpc 1.33
./02-eks/eks-training-bootstrap.sh student1 vpc-xxxxxxxx 1.33
```

The bootstrap script uses `us-east-2` as the fixed region.

Reference template:

```bash
less 02-eks/cluster.full-reference.yaml
```

Use it only as a reference for possible eksctl options. To inspect the exact schema supported by your installed `eksctl` version:

```bash
eksctl utils schema
```

3. Review the generated YAML:

```bash
less 02-eks/cluster.generated.yaml
```

4. Create the cluster manually after review:

```bash
eksctl create cluster -f 02-eks/cluster.generated.yaml
```

If you run the bootstrap script from inside `02-eks`, the generated file is `cluster.generated.yaml` in the current directory.

5. Configure local kubeconfig and OIDC:

```bash
./02-eks/post-create.sh student1 us-east-2
```

This configures kubeconfig for the current AWS caller and verifies:

```bash
kubectl auth can-i get nodes
kubectl get nodes
```

Optionally grant another IAM user or role cluster-admin access:

```bash
./02-eks/post-create.sh student1 us-east-2 student1-admin
./02-eks/post-create.sh student1 us-east-2 arn:aws:iam::123456789012:role/trainer-admin
```

The extra IAM user or role must use its own AWS credentials and run:

```bash
aws eks update-kubeconfig --name student1 --region us-east-2
kubectl get nodes
```

## Post-creation checks

Set common variables:

```bash
export CLUSTER_NAME=student1
export REGION=us-east-2
```

Check clusters:

```bash
eksctl get cluster --region $REGION
eksctl get cluster --name $CLUSTER_NAME --region $REGION
eksctl utils describe-stacks --cluster $CLUSTER_NAME --region $REGION
```

Check managed node groups:

```bash
eksctl get nodegroup --cluster $CLUSTER_NAME --region $REGION
eksctl get nodegroup --cluster $CLUSTER_NAME --region $REGION -o yaml
```

Check EKS add-ons:

```bash
eksctl get addon --cluster $CLUSTER_NAME --region $REGION
eksctl get addon --cluster $CLUSTER_NAME --region $REGION -o yaml
```

Check OIDC and IAM service accounts:

```bash
eksctl utils associate-iam-oidc-provider \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --dry-run

eksctl get iamserviceaccount --cluster $CLUSTER_NAME --region $REGION
eksctl get iamserviceaccount --cluster $CLUSTER_NAME --region $REGION -o yaml
```

Check EKS access entries:

```bash
eksctl get accessentry --cluster $CLUSTER_NAME --region $REGION
eksctl get accessentry --cluster $CLUSTER_NAME --region $REGION -o yaml
```

Refresh kubeconfig:

```bash
eksctl utils write-kubeconfig \
  --cluster $CLUSTER_NAME \
  --region $REGION
```

Check cluster details with AWS CLI:

```bash
aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --query "cluster.{Status:status,Version:version,Endpoint:endpoint,UpgradePolicy:upgradePolicy.supportType}"
```

Check Kubernetes resources:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get events -A --sort-by=.lastTimestamp
```

Preview cluster deletion command:

```bash
eksctl delete cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --dry-run
```

## Delete cluster

Delete by cluster name:

```bash
./02-eks/delete-cluster.sh student1
```

Delete using the generated config file:

```bash
./02-eks/delete-cluster.sh student1 02-eks/cluster.generated.yaml
```

The delete script uses `us-east-2` as the fixed region and waits until `eksctl` finishes deleting the cluster.
