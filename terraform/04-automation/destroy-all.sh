#!/usr/bin/env bash
# Destroy every cluster currently present as a Terraform workspace.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTERS_DIR="${SCRIPT_DIR}/../02-clusters"

cd "${CLUSTERS_DIR}"
terraform init -input=false >/dev/null

WORKSPACES=$(terraform workspace list | sed 's/[* ]//g' | grep -v '^default$' | grep -v '^$')

cd "${SCRIPT_DIR}"
for CLUSTER in ${WORKSPACES}; do
  echo "=== Destroying ${CLUSTER} ==="
  "${SCRIPT_DIR}/destroy-one.sh" "${CLUSTER}"
done

echo ">>> All clusters destroyed."
