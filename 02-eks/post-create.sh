#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <cluster-name> <region>"
  exit 1
fi

CLUSTER_NAME="$1"
REGION="$2"

eksctl utils associate-iam-oidc-provider \
  --cluster "$CLUSTER_NAME" \
  --region "$REGION" \
  --approve

aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query 'cluster.identity.oidc.issuer' \
  --output text

kubectl get nodes
