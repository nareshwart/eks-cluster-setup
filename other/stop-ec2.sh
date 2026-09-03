#!/bin/bash

# =============================================
# EC2 Instance Auto-Stop Script
# 1. Stops all learner VMs immediately
# 2. Schedules trainer VM self-stop after 30 min
# =============================================

REGION="us-east-2"
LOG_FILE="/etc/ansible/ec2-stop.log"
EXCLUDE_NAME="trainer"
SELF_STOP_DELAY=30           # Minutes before trainer VM stops itself
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "============================================" >> $LOG_FILE
echo "[$DATE] Starting EC2 stop process..." >> $LOG_FILE
echo "[$DATE] Excluding instances with Name tag: '$EXCLUDE_NAME'" >> $LOG_FILE

# -----------------------------------------------
# STEP 1: Stop all learner VMs (exclude trainer)
# -----------------------------------------------
# NOTE: AWS EC2 filters do NOT support "!" negation on tag values.
# Fix: Fetch all running instances with their Name tag, then
#      exclude the trainer VM using grep -v in shell.
INSTANCE_IDS=$(aws ec2 describe-instances \
    --region $REGION \
    --filters "Name=instance-state-name,Values=running" \
    --query "Reservations[*].Instances[*].[InstanceId, Tags[?Key=='Name'].Value | [0]]" \
    --output text \
    | grep -v "$EXCLUDE_NAME" \
    | awk '{print $1}')

if [ -z "$INSTANCE_IDS" ]; then
    echo "[$DATE] No learner instances found. Skipping learner stop." >> $LOG_FILE
else
    echo "[$DATE] Stopping learner instances: $INSTANCE_IDS" >> $LOG_FILE
    aws ec2 stop-instances \
        --region $REGION \
        --instance-ids $INSTANCE_IDS >> $LOG_FILE 2>&1
    echo "[$DATE] Learner VMs stop command sent successfully." >> $LOG_FILE
fi

# -----------------------------------------------
# STEP 2: Schedule trainer VM self-stop after 30 min
# -----------------------------------------------
echo "[$DATE] Trainer VM will self-stop in $SELF_STOP_DELAY minutes..." >> $LOG_FILE

# Schedule OS shutdown (this gracefully stops the EC2 instance)
sudo shutdown -h +$SELF_STOP_DELAY "Scheduled trainer VM shutdown after training session." >> $LOG_FILE 2>&1

echo "[$DATE] Self-stop scheduled at $(date -d '+30 minutes' '+%H:%M:%S') UTC" >> $LOG_FILE
echo "============================================" >> $LOG_FILE
