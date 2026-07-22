#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <cluster-name> <region>"
  exit 1
fi

CLUSTER_NAME="$1"
REGION="$2"

echo "Karpenter needs IAM roles, interruption handling, and node class settings that are specific to your account."
echo "Use the official Karpenter getting-started flow for $CLUSTER_NAME in $REGION, then commit the generated values for repeatability."
echo "Docs: https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/"
