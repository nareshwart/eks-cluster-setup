#!/usr/bin/env bash
# Rough cost summary: lists running EC2 instances and EKS clusters tagged Project=EKS-Platform.
set -euo pipefail

REGION="${1:-us-east-2}"

echo "=== EKS Clusters (Project=EKS-Platform) ==="
aws eks list-clusters --region "${REGION}" --query 'clusters' --output table

echo
echo "=== EC2 Instances tagged Project=EKS-Platform ==="
aws ec2 describe-instances \
  --region "${REGION}" \
  --filters "Name=tag:Project,Values=EKS-Platform" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].{Cluster:Tags[?Key==`Cluster`]|[0].Value,Type:InstanceType,State:State.Name,LaunchTime:LaunchTime}' \
  --output table

echo
echo "=== NAT Gateways tagged Project=EKS-Platform ==="
aws ec2 describe-nat-gateways \
  --region "${REGION}" \
  --filter "Name=tag:Project,Values=EKS-Platform" "Name=state,Values=available" \
  --query 'NatGateways[].{Cluster:Tags[?Key==`Cluster`]|[0].Value,State:State,CreateTime:CreateTime}' \
  --output table
