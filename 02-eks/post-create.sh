#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $0 <cluster-name> <region> [admin-iam-user-name|admin-principal-arn]"
  echo
  echo "Examples:"
  echo "  $0 student1 us-east-2"
  echo "  $0 student1 us-east-2 student1-admin"
  echo "  $0 student1 us-east-2 arn:aws:iam::123456789012:user/student1-admin"
  echo "  $0 student1 us-east-2 arn:aws:iam::123456789012:role/trainer-admin"
  exit 1
fi

CLUSTER_NAME="$1"
REGION="$2"
ADMIN_PRINCIPAL="${3:-}"
CURRENT_CALLER_ARN="$(aws sts get-caller-identity --query Arn --output text)"

echo "Current AWS caller: $CURRENT_CALLER_ARN"

if [ -n "$ADMIN_PRINCIPAL" ]; then
  if [[ "$ADMIN_PRINCIPAL" == arn:aws:iam::* ]]; then
    ADMIN_PRINCIPAL_ARN="$ADMIN_PRINCIPAL"
  else
    ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
    ADMIN_PRINCIPAL_ARN="arn:aws:iam::${ACCOUNT_ID}:user/${ADMIN_PRINCIPAL}"
  fi

  echo "Granting EKS cluster-admin access to: $ADMIN_PRINCIPAL_ARN"

  if ! aws eks create-access-entry \
    --cluster-name "$CLUSTER_NAME" \
    --region "$REGION" \
    --principal-arn "$ADMIN_PRINCIPAL_ARN" >/tmp/create-access-entry.err 2>&1; then
    if ! grep -q "ResourceInUseException" /tmp/create-access-entry.err; then
      cat /tmp/create-access-entry.err
      exit 1
    fi
    echo "Access entry already exists for $ADMIN_PRINCIPAL_ARN"
  fi

  if ! aws eks associate-access-policy \
    --cluster-name "$CLUSTER_NAME" \
    --region "$REGION" \
    --principal-arn "$ADMIN_PRINCIPAL_ARN" \
    --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
    --access-scope type=cluster >/tmp/associate-access-policy.err 2>&1; then
    if ! grep -q "ResourceInUseException" /tmp/associate-access-policy.err; then
      cat /tmp/associate-access-policy.err
      exit 1
    fi
    echo "Cluster-admin policy is already associated with $ADMIN_PRINCIPAL_ARN"
  fi
fi

aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
kubectl config current-context

aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query 'cluster.{Name:name,Status:status,Endpoint:endpoint,OIDC:identity.oidc.issuer,UpgradePolicy:upgradePolicy.supportType}' \
  --output text

if [ -n "$ADMIN_PRINCIPAL" ]; then
  aws eks list-associated-access-policies \
    --cluster-name "$CLUSTER_NAME" \
    --region "$REGION" \
    --principal-arn "$ADMIN_PRINCIPAL_ARN" \
    --output table

  cat <<EOF

The admin principal must use its own AWS credentials and run this once before using kubectl:
  aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION

EOF
fi

kubectl auth can-i get nodes
kubectl get nodes
