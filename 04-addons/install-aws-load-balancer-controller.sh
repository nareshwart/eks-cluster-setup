#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <cluster-name> <region>"
  exit 1
fi

CLUSTER_NAME="$1"
REGION="$2"
POLICY_NAME="AWSLoadBalancerControllerIAMPolicy-${CLUSTER_NAME}"
ROLE_NAME="AmazonEKSLoadBalancerControllerRole-${CLUSTER_NAME}"
POLICY_FILE="/tmp/aws-load-balancer-controller-iam-policy.json"

VPC_ID="$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.resourcesVpcConfig.vpcId' --output text)"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

curl -fsSL https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.8.1/docs/install/iam_policy.json -o "$POLICY_FILE"

aws iam create-policy \
  --policy-name "$POLICY_NAME" \
  --policy-document "file://${POLICY_FILE}" >/dev/null 2>&1 || true

eksctl create iamserviceaccount \
  --cluster "$CLUSTER_NAME" \
  --region "$REGION" \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --role-name "$ROLE_NAME" \
  --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}" \
  --approve \
  --override-existing-serviceaccounts

helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

kubectl rollout status deployment/aws-load-balancer-controller -n kube-system
