#!/usr/bin/env bash
set -euo pipefail

REGION="us-east-2"

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "Usage: $0 <cluster-name> [cluster-config-file]"
  echo
  echo "Examples:"
  echo "  $0 student1"
  echo "  $0 student1 cluster.generated.yaml"
  echo
  echo "Region is hard-coded to: $REGION"
  exit 1
fi

CLUSTER_NAME="$1"
CONFIG_FILE="${2:-}"

if [ -n "$CONFIG_FILE" ]; then
  eksctl delete cluster -f "$CONFIG_FILE" --wait
else
  eksctl delete cluster --name "$CLUSTER_NAME" --region "$REGION" --wait
fi
