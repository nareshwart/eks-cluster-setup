#!/bin/bash
# Shell wrapper script to execute EKS cluster teardowns via Cron.
# Logs all execution results with timestamps.

# 1. Define Paths (Essential because Cron runs with a minimal environment)
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
WORKSPACE_DIR="/etc/ansible"
LOG_FILE="/var/tmp/cron_destroy_eks.log"

# 2. Redirect all outputs to log file
exec >> "$LOG_FILE" 2>&1

echo "=========================================================="
echo "📅 [$(date -u +'%Y-%m-%dT%H:%M:%SZ')] Cron Teardown Triggered"
echo "=========================================================="

# 3. Change to working directory
cd "$WORKSPACE_DIR"

# 4. Verify inventory and playbook exist
if [ ! -f "destroy-cluster.yaml" ] || [ ! -f "inventory.ini" ]; then
    echo "❌ Error: Playbook or inventory file not found in $WORKSPACE_DIR."
    exit 1
fi

# 5. Execute the Ansible playbook with high concurrency (25 forks)
echo "⚡ Executing remote destruction playbook..."
ansible-playbook -f 25 -i inventory.ini destroy-cluster.yaml

echo "✅ [$(date -u +'%Y-%m-%dT%H:%M:%SZ')] Cron job execution completed."
echo "=========================================================="
