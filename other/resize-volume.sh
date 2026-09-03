#!/bin/bash
# Bash Script to Resize AWS EBS root volumes to 12GB for STOPPED Learner EC2 Instances.
# Run this on your Trainer VM (where AWS CLI is configured with admin access).

TARGET_SIZE=12
REGION="us-east-2"

echo "🔍 Fetching stopped learner instances from AWS (Name tag containing 'student' or 'learner')..."

# Get Instance details: InstanceId, NameTag, VolumeId
INSTANCES=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=*student*,*learner*" "Name=instance-state-name,Values=stopped" \
    --query "Reservations[*].Instances[*].[InstanceId,Tags[?Key=='Name'].Value | [0], BlockDeviceMappings[?DeviceName=='/dev/xvda' || DeviceName=='/dev/sda1'].Ebs.VolumeId | [0]]" \
    --output text)

if [ -z "$INSTANCES" ] || [ "$INSTANCES" == "None" ]; then
    echo "❌ No STOPPED learner instances found. Check your filters, state, or AWS region."
    exit 1
fi

echo "--------------------------------------------------------"
echo "Instance ID         | Name             | Volume ID"
echo "--------------------------------------------------------"
echo "$INSTANCES"
echo "--------------------------------------------------------"

# Phase 1: Modify EBS volume sizes in AWS
echo "⚡ Modifying physical EBS volume sizes to ${TARGET_SIZE}GB in AWS..."

while read -r instance_id name volume_id; do
    if [ -z "$volume_id" ] || [ "$volume_id" == "None" ]; then
        echo "⚠️  No root volume resolved for $name ($instance_id), skipping..."
        continue
    fi

    echo "⚙️  Resizing volume $volume_id to ${TARGET_SIZE}GB for stopped instance $name ($instance_id)..."
    aws ec2 modify-volume \
        --region "$REGION" \
        --volume-id "$volume_id" \
        --size "$TARGET_SIZE" \
        --output text \
        --query "VolumeModification.ModificationState" >/dev/null

done <<< "$INSTANCES"

echo "--------------------------------------------------------"
echo "✅ AWS Volume modification calls submitted successfully!"
echo "ℹ️  Info: Since the instances are STOPPED, the guest OS filesystem will"
echo "    automatically expand the partition and filesystem on the next boot"
echo "    using the built-in cloud-init growpart module."
echo "--------------------------------------------------------"
