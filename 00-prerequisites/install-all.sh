#!/usr/bin/env bash
# Install every prerequisite for this platform in one go by calling the
# individual install-*.sh scripts in this directory, in a sensible order.
#
# Usage: ./install-all.sh
#
# Each underlying script is idempotent (it checks if the tool is already
# installed and skips re-installing it), so this is safe to re-run any time.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Order: git first (needed to clone), then AWS CLI + session-manager-plugin
# (AWS access), then docker, then the Kubernetes/EKS/Terraform tooling.
SCRIPTS=(
  install-git.sh
  install-aws-cli.sh
  install-session-manager-plugin.sh
  install-kubectl.sh
  install-helm.sh
  install-eksctl.sh
  install-terraform.sh
)

FAILED=()

for script in "${SCRIPTS[@]}"; do
  echo
  echo "=== Installing: ${script} ==="
  if bash "${SCRIPT_DIR}/${script}"; then
    echo "=== OK: ${script} ==="
  else
    echo "=== FAILED: ${script} ==="
    FAILED+=("${script}")
  fi
done

echo
echo "=================================================="
if [ "${#FAILED[@]}" -eq 0 ]; then
  echo "All prerequisites installed successfully."
else
  echo "Completed with failures in: ${FAILED[*]}"
  echo "Re-run this script after resolving the issue(s) above (it's safe to re-run)."
  exit 1
fi
