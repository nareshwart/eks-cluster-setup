#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <cluster-name> <region>"
  exit 1
fi

CLUSTER_NAME="$1"
REGION="$2"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ROLE_NAME="AmazonEKS_EBS_CSI_DriverRole_${CLUSTER_NAME}"

eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster "$CLUSTER_NAME" \
  --region "$REGION" \
  --role-name "$ROLE_NAME" \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve

aws eks create-addon \
  --cluster-name "$CLUSTER_NAME" \
  --region "$REGION" \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}" \
  --resolve-conflicts OVERWRITE || \
aws eks update-addon \
  --cluster-name "$CLUSTER_NAME" \
  --region "$REGION" \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}" \
  --resolve-conflicts OVERWRITE

aws eks wait addon-active --cluster-name "$CLUSTER_NAME" --region "$REGION" --addon-name aws-ebs-csi-driver
