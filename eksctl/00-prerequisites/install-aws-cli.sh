#!/usr/bin/env bash
set -euo pipefail

if command -v aws >/dev/null 2>&1; then
  aws --version
  exit 0
fi

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Darwin)
    if command -v brew >/dev/null 2>&1; then
      brew install awscli
    else
      echo "Homebrew is required on macOS: https://brew.sh"
      exit 1
    fi
    ;;
  Linux)
    case "$ARCH" in
      x86_64) AWS_ARCH="x86_64" ;;
      aarch64|arm64) AWS_ARCH="aarch64" ;;
      *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp
    sudo /tmp/aws/install --update
    ;;
  *)
    echo "Unsupported OS: $OS"
    exit 1
    ;;
esac

aws --version
