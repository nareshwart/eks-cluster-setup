#!/bin/bash

# =============================================
# EC2 Instance Type Modifier
# Finds all stopped t3.small instances and
# upgrades them to t3.medium
# =============================================

REGION="us-east-2"
FROM_TYPE="t3.medium"
TO_TYPE="t3.small"
LOG_FILE="/var/log/ec2-resize.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "============================================" | tee -a $LOG_FILE
echo "[$DATE] Starting instance type modification..." | tee -a $LOG_FILE
echo "[$DATE] Changing: $FROM_TYPE → $TO_TYPE" | tee -a $LOG_FILE
echo "[$DATE] Region: $REGION" | tee -a $LOG_FILE
echo "============================================" | tee -a $LOG_FILE

# -----------------------------------------------
# STEP 1: Find all stopped t3.small instances
# -----------------------------------------------
echo "" | tee -a $LOG_FILE
echo "[$DATE] Fetching stopped $FROM_TYPE instances..." | tee -a $LOG_FILE

INSTANCE_IDS=$(aws ec2 describe-instances \
    --region $REGION \
    --filters \
        "Name=instance-state-name,Values=stopped" \
        "Name=instance-type,Values=$FROM_TYPE" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text)

if [ -z "$INSTANCE_IDS" ]; then
    echo "[$DATE] No stopped $FROM_TYPE instances found. Exiting." | tee -a $LOG_FILE
    exit 0
fi

# Count instances
COUNT=$(echo $INSTANCE_IDS | wc -w)
echo "[$DATE] Found $COUNT instance(s) to resize: $INSTANCE_IDS" | tee -a $LOG_FILE

# -----------------------------------------------
# STEP 2: Modify each instance to t3.medium
# -----------------------------------------------
SUCCESS=0
FAILED=0

for ID in $INSTANCE_IDS; do
    echo "" | tee -a $LOG_FILE
    echo "[$DATE] Modifying $ID → $TO_TYPE ..." | tee -a $LOG_FILE

    aws ec2 modify-instance-attribute \
        --region $REGION \
        --instance-id $ID \
        --instance-type "{\"Value\": \"$TO_TYPE\"}" 2>> $LOG_FILE

    if [ $? -eq 0 ]; then
        echo "[$DATE] ✅ $ID successfully updated to $TO_TYPE" | tee -a $LOG_FILE
        SUCCESS=$((SUCCESS + 1))
    else
        echo "[$DATE] ❌ $ID failed to update — check log for details" | tee -a $LOG_FILE
        FAILED=$((FAILED + 1))
    fi
done

# -----------------------------------------------
# STEP 3: Summary
# -----------------------------------------------
echo "" | tee -a $LOG_FILE
echo "============================================" | tee -a $LOG_FILE
echo "[$DATE] DONE — Success: $SUCCESS | Failed: $FAILED" | tee -a $LOG_FILE
echo "============================================" | tee -a $LOG_FILE

# -----------------------------------------------
# STEP 4: Verify — show updated instance types
# -----------------------------------------------
echo "" | tee -a $LOG_FILE
echo "[$DATE] Verification — current instance types:" | tee -a $LOG_FILE
aws ec2 describe-instances \
    --region $REGION \
    --instance-ids $INSTANCE_IDS \
    --query "Reservations[*].Instances[*].[InstanceId, InstanceType, State.Name, Tags[?Key=='Name'].Value | [0]]" \
    --output table | tee -a $LOG_FILE
