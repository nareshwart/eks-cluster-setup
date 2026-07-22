#!/usr/bin/env bash
# Generate a kubeconfig for a cluster.
# Usage: ./generate-kubeconfig.sh dev01 [region]
set -euo pipefail

CLUSTER="${1:?Usage: generate-kubeconfig.sh <cluster_name> [region]}"
REGION="${2:-us-east-2}"
CLUSTER_NAME="eks-${CLUSTER}-cluster"
OUTFILE="kubeconfig-${CLUSTER}"

aws eks update-kubeconfig \
  --name "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --alias "${CLUSTER}" \
  --kubeconfig "${OUTFILE}"

echo ">>> Kubeconfig written to ${OUTFILE}"
echo "    export KUBECONFIG=\$(pwd)/${OUTFILE}"
