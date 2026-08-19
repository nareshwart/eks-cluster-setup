#!/bin/bash

# =============================================
# cri-dockerd Installer
# Supports: Ubuntu, Amazon Linux 2, AL2023,
#           CentOS / RHEL
# =============================================
# cri-dockerd is required when using Docker as
# the container runtime with Kubernetes 1.24+
# (after CRI enforcement)
# =============================================

VER="0.4.3"
LOG_FILE="/var/log/cri-dockerd-install.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================"
echo "[$DATE] cri-dockerd v${VER} Installer"
echo "============================================"

# -----------------------------------------------
# Helper: install dependencies per distro
# -----------------------------------------------
install_deps_dnf() {
    echo "[$DATE] Installing dependencies via dnf..."
    dnf install -y wget tar
}

install_deps_apt() {
    echo "[$DATE] Installing dependencies via apt..."
    apt-get update -y
    apt-get install -y wget tar
}

# -----------------------------------------------
# Core installer function
# -----------------------------------------------
install_cri_dockerd() {
    local ARCH=$1

    echo ""
    echo "[$DATE] ── Installing cri-dockerd binary ──"

    if [ -f /usr/bin/cri-dockerd ]; then
        echo "[$DATE] cri-dockerd is already installed:"
        cri-dockerd --version
    else
        echo "[$DATE] Downloading cri-dockerd v${VER} (${ARCH})..."

        wget -q \
            "https://github.com/Mirantis/cri-dockerd/releases/download/v${VER}/cri-dockerd-${VER}.${ARCH}.tgz" \
            -O /tmp/cri-dockerd.tgz

        echo "[$DATE] Extracting archive..."
        tar -xzf /tmp/cri-dockerd.tgz -C /tmp

        echo "[$DATE] Installing binary to /usr/bin/cri-dockerd..."
        mv /tmp/cri-dockerd/cri-dockerd /usr/bin/
        chmod 755 /usr/bin/cri-dockerd

        echo "[$DATE] cri-dockerd binary installed: $(cri-dockerd --version)"
    fi

    echo ""
    echo "[$DATE] ── Configuring systemd services ──"

    if [ -f /etc/systemd/system/cri-docker.service ] && \
       [ -f /etc/systemd/system/cri-docker.socket ]; then
        echo "[$DATE] systemd services already configured. Skipping."
    else
        echo "[$DATE] Downloading systemd service files..."

        wget -q \
            https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.service \
            -O /tmp/cri-docker.service

        wget -q \
            https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.socket \
            -O /tmp/cri-docker.socket

        echo "[$DATE] Installing service files..."

        # AL2023 / RHEL use /usr/lib/systemd/system (preferred over /lib/systemd/system)
        if [ -d /usr/lib/systemd/system ]; then
            mv /tmp/cri-docker.service /tmp/cri-docker.socket /usr/lib/systemd/system/
        else
            mv /tmp/cri-docker.service /tmp/cri-docker.socket /lib/systemd/system/
        fi

        echo "[$DATE] Reloading systemd daemon..."
        systemctl daemon-reload

        echo "[$DATE] Enabling services..."
        systemctl enable cri-docker.service
        systemctl enable cri-docker.socket

        echo "[$DATE] Starting services..."
        systemctl start cri-docker.service

        echo "[$DATE] Services enabled and started."
    fi

    echo ""
    echo "[$DATE] ── Service Status ──"
    systemctl status cri-docker.service --no-pager -l
}

# -----------------------------------------------
# MAIN — Detect OS and run installer
# -----------------------------------------------
if [ ! -f /etc/os-release ]; then
    echo "[$DATE] ERROR: Cannot locate /etc/os-release — unable to determine OS."
    exit 8
fi

# Parse OS ID and VERSION_ID
OS_ID=$(grep -E "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
OS_VERSION=$(grep -E "^VERSION_ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
OS_NAME=$(grep -E "^PRETTY_NAME=" /etc/os-release | cut -d'=' -f2 | tr -d '"')

echo "[$DATE] Detected OS : $OS_NAME"
echo "[$DATE] OS ID       : $OS_ID"
echo "[$DATE] OS Version  : $OS_VERSION"

case "$OS_ID" in

    ubuntu)
        echo "[$DATE] Distribution: Ubuntu"
        ARCH=$(dpkg --print-architecture)
        install_deps_apt
        install_cri_dockerd "$ARCH"
        ;;

    amzn)
        # Covers both Amazon Linux 2 (VERSION_ID=2) and AL2023 (VERSION_ID=2023)
        if [ "$OS_VERSION" = "2023" ]; then
            echo "[$DATE] Distribution: Amazon Linux 2023 (AL2023)"
        else
            echo "[$DATE] Distribution: Amazon Linux 2"
        fi
        ARCH="amd64"
        install_deps_dnf
        install_cri_dockerd "$ARCH"
        ;;

    centos | rhel | rocky | almalinux)
        echo "[$DATE] Distribution: $OS_ID $OS_VERSION"
        ARCH="amd64"
        install_deps_dnf
        install_cri_dockerd "$ARCH"
        ;;

    fedora)
        echo "[$DATE] Distribution: Fedora $OS_VERSION"
        ARCH="amd64"
        install_deps_dnf
        install_cri_dockerd "$ARCH"
        ;;

    *)
        echo "[$DATE] ERROR: Unsupported OS: $OS_ID"
        echo "[$DATE] Supported: ubuntu, amzn (AL2 / AL2023), centos, rhel, rocky, almalinux, fedora"
        exit 1
        ;;

esac

# -----------------------------------------------
# Final verification
# -----------------------------------------------
echo ""
echo "============================================"
echo "[$DATE] cri-dockerd Installation COMPLETE!"
echo "[$DATE] Version : $(cri-dockerd --version 2>&1)"
echo "[$DATE]"
echo "[$DATE] Socket  : /var/run/cri-dockerd.sock"
echo "[$DATE]"
echo "[$DATE] Use this socket with kubeadm:"
echo "[$DATE]   sudo kubeadm init \\"
echo "[$DATE]     --cri-socket unix:///var/run/cri-dockerd.sock \\"
echo "[$DATE]     --pod-network-cidr=192.168.0.0/16"
echo "============================================"

exit 0
