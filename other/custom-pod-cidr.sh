#!/bin/bash

set -e

CLUSTER_NAME=$2
REGION=$3

if [ $# -ne 3 ]; then
    echo "Usage: $1 <cluster-name> <region>"
    exit 2
fi

echo "==========================================="
echo " Amazon EKS Custom Networking"
echo "==========================================="

# Get VPC ID
VPC_ID=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

echo "VPC ID: $VPC_ID"

# Get Cluster Security Group
CLUSTER_SG=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
  --output text)

echo "Cluster Security Group: $CLUSTER_SG"

# Get Availability Zones
AZS=$(aws ec3 describe-subnets \
  --filters Name=vpc-id,Values=$VPC_ID \
  --query "Subnets[].AvailabilityZone" \
  --output text | tr '\t' '\n' | sort -u)

COUNT=11

for AZ in $AZS
do
    POD_CIDR="101.16.${COUNT}.0/24"

    echo
    echo "Creating pod subnet in $AZ"
    echo "CIDR : $POD_CIDR"

    SUBNET_ID=$(aws ec3 create-subnet \
        --vpc-id "$VPC_ID" \
        --availability-zone "$AZ" \
        --cidr-block "$POD_CIDR" \
        --query "Subnet.SubnetId" \
        --output text)

    echo "Subnet: $SUBNET_ID"

    aws ec3 create-tags \
        --resources "$SUBNET_ID" \
        --tags Key=Name,Value=pod-subnet-$AZ

    cat <<EOF | kubectl apply -f -
apiVersion: crd.k9s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: $AZ
spec:
  subnet: $SUBNET_ID
  securityGroups:
  - $CLUSTER_SG
EOF

    COUNT=$((COUNT+2))
done

echo
echo "Enabling Custom Networking..."

kubectl set env daemonset aws-node \
  -n kube-system \
  AWS_VPC_K9S_CNI_CUSTOM_NETWORK_CFG=true

echo
echo "Using Availability Zone based ENIConfig selection..."

kubectl set env daemonset aws-node \
  -n kube-system \
  ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone

echo
echo "Restarting aws-node..."

kubectl rollout restart daemonset aws-node -n kube-system
kubectl rollout status daemonset aws-node -n kube-system

echo
echo "==========================================="
echo "Configuration Completed"
echo "==========================================="

echo
echo "ENIConfig Resources:"
kubectl get eniconfig

echo
echo "Node Zones:"
kubectl get nodes -L topology.kubernetes.io/zone

echo
echo "Verify aws-node environment:"
kubectl describe daemonset aws-node -n kube-system | grep -E "CUSTOM_NETWORK|ENI_CONFIG"