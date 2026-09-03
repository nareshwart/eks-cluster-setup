#!/bin/bash

# =============================================
# AWS IAM User Creation Script
# Creates IAM users with:
#   - Console (password) login access
#   - ReadOnlyAccess policy attached
#   - Forced password reset on first login
# =============================================

# ── Configuration ──────────────────────────
DEFAULT_PASSWORD="ekstraining@1234"        # Users must change this on first login
READONLY_POLICY_ARN="arn:aws:iam::aws:policy/ReadOnlyAccess"
LOG_FILE="./iam-user-creation.log"
CREDS_FILE="./iam-user-credentials.csv"
DATE=$(date '+%Y-%m-%d %H:%M:%S')
# ───────────────────────────────────────────

# ── User list: "FirstName LastName" ─────────
USERS=(
"user1"
"user2"
)
# ───────────────────────────────────────────

# Redirect all output to log file AND terminal
exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================"
echo "[$DATE] IAM User Creation Started"
echo "[$DATE] Total users : ${#USERS[@]}"
echo "[$DATE] Policy      : ReadOnlyAccess"
echo "[$DATE] Log file    : $LOG_FILE"
echo "[$DATE] Creds file  : $CREDS_FILE"
echo "============================================"
echo ""

# Write CSV header
echo "Username,FullName,Password,ConsoleLoginURL,Status" > "$CREDS_FILE"

SUCCESS=0
SKIPPED=0
FAILED=0

for FULL_NAME in "${USERS[@]}"; do

    # ── Convert "First Last" → "first.last" username
    USERNAME=$(echo "$FULL_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '.')

    echo "--------------------------------------------"
    echo "[$DATE] Processing: $FULL_NAME → $USERNAME"

    # ── Check if user already exists
    if aws iam get-user --user-name "$USERNAME" > /dev/null 2>&1; then
        echo "[$DATE] ⚠️  SKIPPED — User '$USERNAME' already exists."
        echo "$USERNAME,$FULL_NAME,EXISTING,already-exists,SKIPPED" >> "$CREDS_FILE"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # ── STEP 1: Create IAM user
    echo "[$DATE]   Creating IAM user..."
    if ! aws iam create-user --user-name "$USERNAME" \
        --tags Key=Name,Value="$FULL_NAME" Key=Purpose,Value=Training > /dev/null 2>&1; then
        echo "[$DATE] ❌ FAILED to create user '$USERNAME'."
        echo "$USERNAME,$FULL_NAME,FAILED,N/A,FAILED" >> "$CREDS_FILE"
        FAILED=$((FAILED + 1))
        continue
    fi

    # ── STEP 2: Attach ReadOnlyAccess policy
    echo "[$DATE]   Attaching ReadOnlyAccess policy..."
    if ! aws iam attach-user-policy \
        --user-name "$USERNAME" \
        --policy-arn "$READONLY_POLICY_ARN" > /dev/null 2>&1; then
        echo "[$DATE] ❌ FAILED to attach policy to '$USERNAME'."
        echo "$USERNAME,$FULL_NAME,$DEFAULT_PASSWORD,N/A,POLICY_FAILED" >> "$CREDS_FILE"
        FAILED=$((FAILED + 1))
        continue
    fi

    # ── STEP 3: Create console login profile (enable password login)
    echo "[$DATE]   Creating console login profile..."
    if ! aws iam create-login-profile \
        --user-name "$USERNAME" \
        --password "$DEFAULT_PASSWORD" ;then
        echo "[$DATE] ❌ FAILED to create login profile for '$USERNAME'."
        echo "$USERNAME,$FULL_NAME,$DEFAULT_PASSWORD,N/A,LOGIN_FAILED" >> "$CREDS_FILE"
        FAILED=$((FAILED + 1))
        continue
    fi

    # ── Get AWS Account ID for console login URL
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    CONSOLE_URL="https://${ACCOUNT_ID}.signin.aws.amazon.com/console"

    echo "[$DATE] ✅ Created: $USERNAME | URL: $CONSOLE_URL"
    echo "$USERNAME,$FULL_NAME,$DEFAULT_PASSWORD,$CONSOLE_URL,SUCCESS" >> "$CREDS_FILE"
    SUCCESS=$((SUCCESS + 1))

done

# ── Summary ─────────────────────────────────
echo ""
echo "============================================"
echo "[$DATE] DONE!"
echo "[$DATE]   ✅ Created  : $SUCCESS"
echo "[$DATE]   ⚠️  Skipped  : $SKIPPED (already existed)"
echo "[$DATE]   ❌ Failed   : $FAILED"
echo "[$DATE]"
echo "[$DATE] Credentials saved to: $CREDS_FILE"
echo "[$DATE] Full log saved to   : $LOG_FILE"
echo "[$DATE]"
echo "[$DATE] Share with users:"
echo "[$DATE]   Console URL : https://<ACCOUNT_ID>.signin.aws.amazon.com/console"
echo "[$DATE]   Username    : firstname.lastname  (e.g., amit.chaurasiya)"
echo "[$DATE]   Password    : $DEFAULT_PASSWORD"
echo "============================================"

# ── Print credentials table ─────────────────
echo ""
echo "── Credentials Summary ──────────────────"
column -t -s',' "$CREDS_FILE"
echo "─────────────────────────────────────────"
