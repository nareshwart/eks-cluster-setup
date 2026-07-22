#!/usr/bin/env bash
# Destroy a single EKS cluster.
# Usage: ./destroy-one.sh dev01
set -euo pipefail

CLUSTER="${1:?Usage: destroy-one.sh <cluster_name>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTERS_DIR="${SCRIPT_DIR}/../02-clusters"

cd "${CLUSTERS_DIR}"

terraform init -input=false >/dev/null

if ! terraform workspace list | grep -qE "(^|\s)${CLUSTER}(\s|$)"; then
  echo "No workspace found for ${CLUSTER}, nothing to destroy."
  exit 0
fi

terraform workspace select "${CLUSTER}"

echo ">>> Destroying cluster ${CLUSTER}"
terraform destroy -auto-approve -var="cluster_name=${CLUSTER}"

terraform workspace select default
terraform workspace delete "${CLUSTER}"

echo ">>> Destroyed and removed workspace for ${CLUSTER}"
