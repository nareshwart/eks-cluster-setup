#!/usr/bin/env bash
set -euo pipefail

if command -v kubectl >/dev/null 2>&1; then
  kubectl version --client=true
  exit 0
fi

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64) KUBE_ARCH="amd64" ;;
  aarch64|arm64) KUBE_ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

case "$OS" in
  Darwin)
    if command -v brew >/dev/null 2>&1; then
      brew install kubectl
    else
      echo "Homebrew is required on macOS: https://brew.sh"
      exit 1
    fi
    ;;
  Linux)
    VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
    curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${VERSION}/bin/linux/${KUBE_ARCH}/kubectl"
    sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
    ;;
  *)
    echo "Unsupported OS: $OS"
    exit 1
    ;;
esac

kubectl version --client=true
