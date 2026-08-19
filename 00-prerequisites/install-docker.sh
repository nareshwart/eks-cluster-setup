#!/bin/bash

# =============================================
# Install Latest Docker CE on Amazon Linux 2023
# =============================================
# AL2023 does NOT use amazon-linux-extras.
# This script adds Docker's official repo and
# installs the latest Docker CE via dnf.
# =============================================

set -e  # Exit immediately on any error

LOG_FILE="/var/log/docker-install.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Redirect all output to log file AND terminal
exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================"
echo "[$DATE] Docker Installation Started"
echo "[$DATE] OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2)"
echo "============================================"

# -----------------------------------------------
# STEP 1: Remove any old/conflicting packages
# -----------------------------------------------
echo ""
echo "[$DATE] STEP 1: Removing old Docker packages (if any)..."

dnf remove -y docker \
    docker-client \
    docker-client-latest \
    docker-common \
    docker-latest \
    docker-latest-logrotate \
    docker-logrotate \
    docker-engine \
    podman \
    runc 2>/dev/null || true

echo "[$DATE] Old packages cleaned up."

# -----------------------------------------------
# STEP 2: Install required dependencies
# -----------------------------------------------
echo ""
echo "[$DATE] STEP 2: Installing required dependencies..."

# NOTE: AL2023 ships with curl-minimal by default.
# Installing the full 'curl' package conflicts with curl-minimal.
# curl-minimal is sufficient for Docker repo setup — do NOT install curl.
dnf install -y \
    dnf-plugins-core \
    git

echo "[$DATE] Dependencies installed."


# -----------------------------------------------
# STEP 3: Add Docker's official repository
# -----------------------------------------------
echo ""
echo "[$DATE] STEP 3: Adding Docker's official repository..."

# NOTE: AL2023 version string (e.g. 2023.12.xxx) breaks dnf config-manager
# auto-detection — it generates a 404 URL. Fix: manually write the repo file
# using the explicit RHEL 9 baseurl (AL2023 is RHEL 9 compatible).

cat > /etc/yum.repos.d/docker-ce.repo << 'EOF'
[docker-ce-stable]
name=Docker CE Stable - $basearch
baseurl=https://download.docker.com/linux/rhel/9/$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/rhel/gpg

[docker-ce-stable-debuginfo]
name=Docker CE Stable - Debuginfo $basearch
baseurl=https://download.docker.com/linux/rhel/9/debug-$basearch/stable
enabled=0
gpgcheck=1
gpgkey=https://download.docker.com/linux/rhel/gpg
EOF

echo "[$DATE] Docker repo file created at /etc/yum.repos.d/docker-ce.repo"
dnf makecache
echo "[$DATE] Docker repo metadata refreshed."

# -----------------------------------------------
# STEP 4: Install Docker CE (latest version)
# -----------------------------------------------
echo ""
echo "[$DATE] STEP 4: Installing Docker CE (latest)..."

dnf install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

echo "[$DATE] Docker CE installed successfully."

# -----------------------------------------------
# STEP 5: Enable and Start Docker service
# -----------------------------------------------
echo ""
echo "[$DATE] STEP 5: Enabling and starting Docker service..."

systemctl enable docker
systemctl start docker

echo "[$DATE] Docker service started."

# -----------------------------------------------
# STEP 6: Add ec2-user to docker group
# (Run docker without sudo)
# -----------------------------------------------
echo ""
echo "[$DATE] STEP 6: Adding ec2-user to docker group..."

usermod -aG docker ec2-user

echo "[$DATE] ec2-user added to docker group."

# -----------------------------------------------
# STEP 7: Verify Installation
# -----------------------------------------------
echo ""
echo "[$DATE] STEP 7: Verifying Docker installation..."

DOCKER_VERSION=$(docker --version)
COMPOSE_VERSION=$(docker compose version)

echo "[$DATE] $DOCKER_VERSION"
echo "[$DATE] $COMPOSE_VERSION"

echo ""
echo "[$DATE] Docker service status:"
systemctl status docker --no-pager -l

# -----------------------------------------------
# STEP 8: Run hello-world to confirm it works
# -----------------------------------------------
echo ""
echo "[$DATE] STEP 8: Running docker hello-world test..."
docker run --rm hello-world

echo ""
echo "============================================"
echo "[$DATE] Docker Installation COMPLETE!"
echo "[$DATE] Docker Version : $DOCKER_VERSION"
echo "[$DATE] Compose Version: $COMPOSE_VERSION"
echo "[$DATE]"
echo "[$DATE] IMPORTANT: Log out and back in (or run 'newgrp docker')"
echo "[$DATE] for the docker group to take effect for ec2-user."
echo "============================================"
