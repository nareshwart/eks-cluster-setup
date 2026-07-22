#!/bin/bash
set -euo pipefail

if [ -f /etc/os-release ]; then
  . /etc/os-release
else
  echo "Unsupported OS"
  exit 1
fi

ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

if [[ "$ID" == "amzn" ]]; then
  sudo dnf -y install curl tar gzip unzip >/dev/null 2>&1 || sudo yum -y install curl tar gzip unzip
elif [[ "$ID" == "ubuntu" ]]; then
  sudo apt-get update
  sudo apt-get install -y curl tar gzip unzip
else
  echo "Only Amazon Linux and Ubuntu are supported."
  exit 1
fi

OS=Linux
curl -sSL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_${OS}_${ARCH}.tar.gz" -o /tmp/eksctl.tar.gz
tar -xzf /tmp/eksctl.tar.gz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin/
sudo chmod +x /usr/local/bin/eksctl

echo
echo "eksctl installed successfully"
eksctl version
echo "Binary: $(which eksctl)"
