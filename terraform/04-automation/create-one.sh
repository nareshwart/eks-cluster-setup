#!/usr/bin/env bash
# Create a single EKS cluster.
# Usage: ./create-one.sh dev01
set -euo pipefail

CLUSTER="${1:?Usage: create-one.sh <cluster_name>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTERS_DIR="${SCRIPT_DIR}/../02-clusters"

cd "${CLUSTERS_DIR}"

terraform init -input=false >/dev/null

if terraform workspace list | grep -qE "(^|\s)${CLUSTER}(\s|$)"; then
  terraform workspace select "${CLUSTER}"
else
  terraform workspace new "${CLUSTER}"
fi

echo ">>> Applying cluster ${CLUSTER}"
terraform apply -auto-approve -var="cluster_name=${CLUSTER}"

echo ">>> Done. Generate a kubeconfig with: ../automation/generate-kubeconfig.sh ${CLUSTER}"
