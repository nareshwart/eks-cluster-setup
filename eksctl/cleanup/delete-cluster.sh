#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $0 <cluster-name> <region> [cluster-config-file]"
  exit 1
fi

CLUSTER_NAME="$1"
REGION="$2"
CONFIG_FILE="${3:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ -n "$CONFIG_FILE" ]; then
  "${REPO_ROOT}/02-eks/delete-cluster.sh" "$CLUSTER_NAME" "$CONFIG_FILE"
else
  if [ "$REGION" != "us-east-2" ]; then
    echo "02-eks/delete-cluster.sh uses us-east-2. Received region: $REGION"
    exit 1
  fi
  "${REPO_ROOT}/02-eks/delete-cluster.sh" "$CLUSTER_NAME"
fi
