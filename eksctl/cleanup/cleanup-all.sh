#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "Usage: $0 <cluster-name> <region> <vpc-id>"
  exit 1
fi

CLUSTER_NAME="$1"
REGION="$2"
VPC_ID="$3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/delete-cluster.sh" "$CLUSTER_NAME" "$REGION"
"${SCRIPT_DIR}/delete-vpc.sh" "$REGION" "$VPC_ID"
