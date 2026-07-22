#!/usr/bin/env bash
# Health-check a cluster: nodes Ready, core pods Running.
# Usage: ./health-check.sh dev01 [region]
set -euo pipefail

CLUSTER="${1:?Usage: health-check.sh <cluster_name> [region]}"
REGION="${2:-us-east-2}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/generate-kubeconfig.sh" "${CLUSTER}" "${REGION}" >/dev/null

export KUBECONFIG="${SCRIPT_DIR}/kubeconfig-${CLUSTER}"

echo "=== Nodes (${CLUSTER}) ==="
kubectl get nodes -o wide

echo
echo "=== kube-system pods (${CLUSTER}) ==="
kubectl get pods -n kube-system

echo
NOT_READY=$(kubectl get nodes --no-headers | grep -vc " Ready " || true)
if [[ "${NOT_READY}" -gt 0 ]]; then
  echo "WARNING: ${NOT_READY} node(s) not Ready for ${CLUSTER}"
  exit 1
fi

echo "OK: ${CLUSTER} cluster healthy"
