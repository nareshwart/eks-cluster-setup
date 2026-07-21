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

Delete a VPC after the cluster and load balancers are gone. You can pass either the VPC ID or the VPC `Name` tag:

```bash
./01-network/delete-vpc.sh us-east-2 vpc-xxxxxxxx
./01-network/delete-vpc.sh us-east-2 student1-vpc
```
