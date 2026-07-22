#!/usr/bin/env bash
set -euo pipefail

if command -v eksctl >/dev/null 2>&1; then
  eksctl version
  exit 0
fi

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64) EKSCTL_ARCH="amd64" ;;
  aarch64|arm64) EKSCTL_ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

case "$OS" in
  Darwin)
    if command -v brew >/dev/null 2>&1; then
      brew install eksctl
    else
      echo "Homebrew is required on macOS: https://brew.sh"
      exit 1
    fi
    ;;
  Linux)
    curl -fsSL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_${EKSCTL_ARCH}.tar.gz" -o /tmp/eksctl.tar.gz
    tar -xzf /tmp/eksctl.tar.gz -C /tmp
    sudo install -m 0755 /tmp/eksctl /usr/local/bin/eksctl
    ;;
  *)
    echo "Unsupported OS: $OS"
    exit 1
    ;;
esac

eksctl version
