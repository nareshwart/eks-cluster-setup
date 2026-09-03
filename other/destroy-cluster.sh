#!/bin/bash
# Script to locate the initialized EKS workspace and trigger teardown.
# This script runs on the Student VM.

set -e

# Target paths to check
PATHS=(
  "/root/eks-cluster-setup"
  "/home/devops/eks-cluster-setup"
)

TARGET_SUBDIR="terraform/03-examples/single-cluster"
RESOLVED_DIR=""

echo "🔍 Searching for 'eks-cluster-setup' directory..."

for base_path in "${PATHS[@]}"; do
    if [ -d "$base_path" ]; then
        echo "📂 Found directory: $base_path"

        # Define path to EKS workspace folder
        tf_dir="$base_path/$TARGET_SUBDIR"

        # Check if Terraform was initialized (.terraform folder exists)
        if [ -d "$tf_dir/.terraform" ]; then
            echo "✅ Terraform is INITIALIZED in: $tf_dir"
            RESOLVED_DIR="$tf_dir"
            break
        else
            echo "⚠️  Found directory at $base_path, but Terraform is NOT initialized in: $tf_dir"
        fi
    fi
done

if [ -z "$RESOLVED_DIR" ]; then
    echo "❌ Error: Could not locate a valid 'eks-cluster-setup' directory containing an initialized Terraform environment."
    exit 1
fi

echo "⚡ Changing directory to: $RESOLVED_DIR"
cd "$RESOLVED_DIR"

echo "⚙️  Triggering EKS Cluster Teardown..."
# Attempt to run terraform destroy
if ! terraform destroy -auto-approve; then
    echo "⚠️  Teardown blocked by unreachable Kubernetes API. Cleaning state..."

    # List all helm and kubernetes resources and remove them from state
    terraform state list | grep -E "(kubernetes_|helm_)" | xargs -I {} terraform state rm {} || true

    echo "⚡ Retrying destroy for remaining AWS VPC resources..."
    terraform destroy -auto-approve
fi

echo "✅ Cluster teardown completed successfully!"
