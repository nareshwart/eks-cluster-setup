# 02-eks

Generates and creates an EKS cluster with `eksctl`.

1. Create the VPC first:

```bash
./01-network/create-vpc.sh us-east-2 student1 10.50.0.0/16
```

2. Generate an eksctl config:

```bash
./02-eks/eks-training-bootstrap.sh us-east-2 student1 vpc-xxxxxxxx 1.33
```

3. Create the cluster:

```bash
eksctl create cluster -f 02-eks/cluster.generated.yaml
```

4. Configure local kubeconfig and OIDC:

```bash
./02-eks/post-create.sh student1 us-east-2
```
