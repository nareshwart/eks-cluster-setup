#!/bin/bash
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <cluster-name> <region>"
  echo "Example: $0 student1 us-east-2"
  exit 1
fi

CLUSTER_NAME="$1"
REGION="$2"

echo "======================================"
echo "Post EKS Configuration"
echo "======================================"

echo "[1/4] Associating IAM OIDC Provider..."
eksctl utils associate-iam-oidc-provider \
  --cluster "$CLUSTER_NAME" \
  --region "$REGION" \
  --approve

echo
echo "[2/4] Verifying OIDC Issuer..."
aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query "cluster.identity.oidc.issuer" \
  --output text

echo
echo "[3/4] Listing installed EKS add-ons..."
aws eks list-addons \
  --cluster-name "$CLUSTER_NAME" \
  --region "$REGION"

cat <<'EOF'

=========================================
Next Steps
=========================================

1. Get the cluster security group:

aws eks describe-cluster   --name <cluster-name>   --region <region>   --query "cluster.resourcesVpcConfig.clusterSecurityGroupId"   --output text

2. Create ENIConfig resources for each pod subnet.

Example:

apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: us-east-2a
spec:
  subnet: <pod-subnet-id>
  securityGroups:
    - <cluster-security-group>

3. Enable custom networking:

kubectl set env daemonset aws-node   -n kube-system   AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true

kubectl set env daemonset aws-node   -n kube-system   ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone

kubectl rollout restart daemonset aws-node -n kube-system
kubectl rollout status daemonset aws-node -n kube-system

4. Verify:

kubectl get nodes
kubectl get eniconfig
kubectl get pods -A -o wide

=========================================

EOF
