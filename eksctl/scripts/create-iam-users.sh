#!/bin/bash

# ==========================================================
# AWS IAM Learner User Creation Script
# Creates learner01 - learner25
# Password: ekatraining
# Policy: ReadOnlyAccess
# ==========================================================

set -e

PASSWORD="ekstraining@1234"
POLICY_ARN="arn:aws:iam::aws:policy/ReadOnlyAccess"

echo "========================================="
echo " Creating IAM Learner Users"
echo "========================================="

for i in $(seq -w 1 25)
do
    USER="learner${i}"

    echo ""
    echo "Processing ${USER}..."

    # Check if user already exists
    if aws iam get-user --user-name "${USER}" >/dev/null 2>&1; then
        echo "User ${USER} already exists. Skipping..."
        continue
    fi

    # Create IAM User
    aws iam create-user \
        --user-name "${USER}"

    # Create Console Login Password
    aws iam create-login-profile \
        --user-name "${USER}" \
        --password "${PASSWORD}" \

    # Attach ReadOnly Policy
    aws iam attach-user-policy \
        --user-name "${USER}" \
        --policy-arn "${POLICY_ARN}"

    echo "Created ${USER}"
done

echo ""
echo "========================================="
echo "Completed Successfully!"
echo "========================================="
echo ""
echo "Username Pattern : learner01 - learner25"
echo "Initial Password : ${PASSWORD}"
echo "Permission       : ReadOnlyAccess"