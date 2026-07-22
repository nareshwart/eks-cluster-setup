#!/usr/bin/env bash
# Create every cluster defined in clusters.auto.tfvars.json.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTERS_DIR="${SCRIPT_DIR}/../02-clusters"
TFVARS_FILE="${CLUSTERS_DIR}/clusters.auto.tfvars.json"

CLUSTERS=$(jq -r '.clusters | keys[]' "${TFVARS_FILE}")

for CLUSTER in ${CLUSTERS}; do
  echo "=== Creating ${CLUSTER} ==="
  "${SCRIPT_DIR}/create-one.sh" "${CLUSTER}" &
done

wait
echo ">>> All clusters created."
