#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <cluster-name> <region> [cluster-config-file]"
  exit 1
fi

CLUSTER_NAME="$1"
REGION="$2"
CONFIG_FILE="${3:-}"

if [ -n "$CONFIG_FILE" ]; then
  eksctl delete cluster -f "$CONFIG_FILE" --wait
else
  eksctl delete cluster --name "$CLUSTER_NAME" --region "$REGION" --wait
fi
