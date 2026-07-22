# 03-custom-networking

Enables Amazon VPC CNI custom networking so pods use the secondary VPC CIDR subnets.

Run after the EKS cluster is created and kubeconfig is active:

```bash
./03-custom-networking/enable-custom-networking.sh student1
```

The script uses `us-east-2` as the fixed region.

The script:

- Finds pod subnets in the cluster VPC
- Creates one `ENIConfig` per Availability Zone
- Enables `AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG`
- Selects ENIConfig objects using `topology.kubernetes.io/zone`
- Restarts the `aws-node` DaemonSet
