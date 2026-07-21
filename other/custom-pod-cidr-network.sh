#!/bin/bash

set -e

CLUSTER=$1
REGION=$2
CLUSTER_ID=$3

if [ $# -ne 3 ]; then
    echo
    echo "Usage:"
    echo
    echo "./configure-custom-networking.sh <cluster> <region> <cluster-id>"
    echo
    exit 1
fi

START=$(( (CLUSTER_ID-1)*3 + 1 ))

SUBNET1="pod-subnet-${START}"
SUBNET2="pod-subnet-$((START+1))"
SUBNET3="pod-subnet-$((START+2))"

echo
echo "Cluster      : $CLUSTER"
echo "Cluster ID   : $CLUSTER_ID"
echo
echo "Finding pod subnets..."

SUBNET_A=$(aws ec2 describe-subnets \
--filters Name=tag:Name,Values=$SUBNET1 \
--query "Subnets[0].SubnetId" \
--output text)

SUBNET_B=$(aws ec2 describe-subnets \
--filters Name=tag:Name,Values=$SUBNET2 \
--query "Subnets[0].SubnetId" \
--output text)

SUBNET_C=$(aws ec2 describe-subnets \
--filters Name=tag:Name,Values=$SUBNET3 \
--query "Subnets[0].SubnetId" \
--output text)

echo
echo $SUBNET_A
echo $SUBNET_B
echo $SUBNET_C

SG=$(aws eks describe-cluster \
--name $CLUSTER \
--region $REGION \
--query cluster.resourcesVpcConfig.clusterSecurityGroupId \
--output text)

cat <<EOF | kubectl apply -f -

apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: us-east-2a
spec:
  subnet: $SUBNET_A
  securityGroups:
    - $SG

---

apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: us-east-2b
spec:
  subnet: $SUBNET_B
  securityGroups:
    - $SG

---

apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: us-east-2c
spec:
  subnet: $SUBNET_C
  securityGroups:
    - $SG

EOF

kubectl set env daemonset aws-node \
-n kube-system \
AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true

kubectl set env daemonset aws-node \
-n kube-system \
ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone

kubectl rollout restart ds aws-node -n kube-system

kubectl rollout status ds aws-node -n kube-system

echo
echo "Completed Successfully."