# 01-network

Creates the VPC used by the EKS training cluster.

```bash
./01-network/create-vpc.sh us-east-2 student1 10.50.0.0/16
```

The script creates:

- VPC with DNS support
- Internet gateway and public route table
- 3 public subnets for EKS nodes and load balancers
- Secondary VPC CIDR `100.64.0.0/16`
- 3 pod subnets for VPC CNI custom networking
- EKS subnet discovery tags:
  - public subnets: `kubernetes.io/role/elb=1`
  - pod subnets: `kubernetes.io/role/internal-elb=1`
  - all EKS subnets: `kubernetes.io/cluster/<cluster-name>=shared`
- Consistent `Name`, `Project`, `Cluster`, and `ManagedBy` tags

By default, pod subnets only have local VPC routing. If you want pods that use custom networking to reach the internet, create a NAT gateway by setting:

```bash
ENABLE_NAT_GATEWAY=true ./01-network/create-vpc.sh us-east-2 student1 10.50.0.0/16
```

NAT gateways and Elastic IPs are billable AWS resources.

Delete a VPC after the cluster and load balancers are gone. You can pass either the VPC ID or the VPC `Name` tag:

```bash
./01-network/delete-vpc.sh us-east-2 vpc-xxxxxxxx
./01-network/delete-vpc.sh us-east-2 student1-vpc
```
