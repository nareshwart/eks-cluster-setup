#!/bin/bash

# =============================================
# Install kubeadm, kubelet, kubectl
# on Amazon Linux 2023 (AL2023)
# =============================================
# Uses the official Kubernetes community repo:
#   pkgs.k8s.io (replaces the deprecated
#   packages.cloud.google.com repo)
# =============================================

set -e

# ── Kubernetes version (hardcoded) ─────────
K8S_VERSION="v1.35"
# ───────────────────────────────────────────


LOG_FILE="/var/log/k8s-install.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================"
echo "[$DATE] Kubernetes Tools Installation"
echo "[$DATE] Version stream  : $K8S_VERSION"
echo "[$DATE] OS              : $(grep PRETTY_NAME /etc/os-release | cut -d= -f2)"
echo "============================================"

# -----------------------------------------------
# STEP 1: Disable Swap (required by kubelet)
# -----------------------------------------------
echo ""
echo "[$DATE] STEP 1: Disabling swap..."

swapoff -a

# Persist across reboots — comment out any swap entries
sed -i '/\bswap\b/s/^/#/' /etc/fstab

echo "[$DATE] Swap disabled."

# -----------------------------------------------
# STEP 2: Set SELinux to Permissive
# -----------------------------------------------
echo ""
echo "[$DATE] STEP 2: Setting SELinux to permissive..."

setenforce 0 2>/dev/null || true

# Persist across reboots
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
sed -i 's/^SELINUX=enabled/SELINUX=permissive/' /etc/selinux/config

echo "[$DATE] SELinux set to permissive."

# -----------------------------------------------
# STEP 3: Load Required Kernel Modules
# -----------------------------------------------
echo ""
echo "[$DATE] STEP 3: Loading kernel modules..."

# Load now
modprobe overlay
modprobe br_netfilter

# Persist across reboots
cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
EOF

echo "[$DATE] Kernel modules loaded: overlay, br_netfilter"

# -----------------------------------------------
# STEP 4: Configure sysctl for Kubernetes networking
# -----------------------------------------------
echo ""
echo "[$DATE] STEP 4: Configuring sysctl networking params..."

cat > /etc/sysctl.d/k8s.conf << 'EOF'
# Allow iptables to see bridged traffic
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
# Enable IP forwarding (required for pod networking)
net.ipv4.ip_forward                 = 1
EOF

# Apply immediately
sysctl --system

echo "[$DATE] sysctl params applied."

# -----------------------------------------------
# STEP 5: Add Kubernetes repo (pkgs.k8s.io)
# -----------------------------------------------
echo ""
echo "[$DATE] STEP 5: Adding Kubernetes repo (pkgs.k8s.io)..."

# NOTE: The old repo (packages.cloud.google.com) is deprecated.
# pkgs.k8s.io is the official Kubernetes community-owned repo.
# AL2023 is RHEL 9 compatible — use the rpm channel.
cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

echo "[$DATE] Kubernetes repo added."
dnf makecache

# -----------------------------------------------
# STEP 6: Install kubelet, kubeadm, kubectl
# -----------------------------------------------
echo ""
echo "[$DATE] STEP 6: Installing kubelet, kubeadm, kubectl..."

# --disableexcludes=kubernetes ensures the excluded packages above
# are installed from the kubernetes repo (not from AL2023 base repos)
dnf install -y \
    kubelet \
    kubeadm \
    kubectl \
    --disableexcludes=kubernetes

echo "[$DATE] kubelet, kubeadm, kubectl installed."

# -----------------------------------------------
# STEP 7: Enable kubelet service
# (kubeadm will fully configure and start it)
# -----------------------------------------------
echo ""
echo "[$DATE] STEP 7: Enabling kubelet service..."

systemctl enable kubelet

echo "[$DATE] kubelet enabled (will start after kubeadm init/join)."

# -----------------------------------------------
# STEP 8: Verify Installation
# -----------------------------------------------
echo ""
echo "[$DATE] STEP 8: Verifying installation..."

KUBEADM_VER=$(kubeadm version -o short 2>/dev/null || kubeadm version)
KUBELET_VER=$(kubelet --version)
KUBECTL_VER=$(kubectl version --client --output=yaml | grep gitVersion | awk '{print $2}')

echo "[$DATE] kubeadm : $KUBEADM_VER"
echo "[$DATE] kubelet : $KUBELET_VER"
echo "[$DATE] kubectl : $KUBECTL_VER"

# -----------------------------------------------
# STEP 9: Lock versions to prevent accidental upgrades
# -----------------------------------------------
echo ""
echo "[$DATE] STEP 9: Locking package versions..."

# 'versionlock' prevents dnf upgrade from accidentally upgrading k8s tools
dnf install -y python3-dnf-plugin-versionlock 2>/dev/null || true
dnf versionlock add kubelet kubeadm kubectl 2>/dev/null || true

echo "[$DATE] Package versions locked."

# -----------------------------------------------
# Summary
# -----------------------------------------------
echo ""
echo "============================================"
echo "[$DATE] INSTALLATION COMPLETE!"
echo "[$DATE]"
echo "[$DATE] kubeadm : $KUBEADM_VER"
echo "[$DATE] kubelet : $KUBELET_VER"
echo "[$DATE] kubectl : $KUBECTL_VER"
echo "[$DATE]"
echo "[$DATE] ── NEXT STEPS ──────────────────────"
echo "[$DATE]"
echo "[$DATE] CONTROL PLANE (run on master node):"
echo "[$DATE]   sudo kubeadm init --pod-network-cidr=192.168.0.0/16"
echo "[$DATE]"
echo "[$DATE] WORKER NODE (run on worker after init):"
echo "[$DATE]   sudo kubeadm join <CONTROL-PLANE-IP>:6443 \\"
echo "[$DATE]     --token <TOKEN> \\"
echo "[$DATE]     --discovery-token-ca-cert-hash sha256:<HASH>"
echo "[$DATE]"
echo "[$DATE] Setup kubectl config (on master):"
echo "[$DATE]   mkdir -p ~/.kube"
echo "[$DATE]   sudo cp /etc/kubernetes/admin.conf ~/.kube/config"
echo "[$DATE]   sudo chown \$(id -u):\$(id -g) ~/.kube/config"
echo "[$DATE]"
echo "[$DATE] Install a CNI plugin (e.g., Calico):"
echo "[$DATE]   kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml"
echo "============================================"
