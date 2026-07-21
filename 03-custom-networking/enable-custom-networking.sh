#!/usr/bin/env bash
set -euo pipefail

REGION="us-east-2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -ne 1 ]; then
  echo "Usage: $0 <cluster-name>"
  echo
  echo "Region is hard-coded to: $REGION"
  exit 1
fi

CLUSTER_NAME="$1"

VPC_ID="$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.resourcesVpcConfig.vpcId' --output text)"
CLUSTER_SG="$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)"

mapfile -t POD_SUBNETS < <(aws ec2 describe-subnets \
  --region "$REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" Name=tag:kubernetes.io/role/internal-elb,Values=1 \
  --query 'sort_by(Subnets,&AvailabilityZone)[].[AvailabilityZone,SubnetId]' \
  --output text)

if [ "${#POD_SUBNETS[@]}" -eq 0 ]; then
  echo "No pod subnets found in $VPC_ID. Expected subnets tagged kubernetes.io/role/internal-elb=1."
  exit 1
fi

for ROW in "${POD_SUBNETS[@]}"; do
  AZ="$(echo "$ROW" | awk '{print $1}')"
  SUBNET_ID="$(echo "$ROW" | awk '{print $2}')"
  sed \
    -e "s/AZ_NAME/${AZ}/g" \
    -e "s/POD_SUBNET_ID/${SUBNET_ID}/g" \
    -e "s/CLUSTER_SECURITY_GROUP_ID/${CLUSTER_SG}/g" \
    "${SCRIPT_DIR}/eniconfig.yaml" | kubectl apply -f -
done

kubectl set env daemonset aws-node -n kube-system AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true
kubectl set env daemonset aws-node -n kube-system ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone
kubectl rollout restart daemonset aws-node -n kube-system
kubectl rollout status daemonset aws-node -n kube-system

kubectl get eniconfig
