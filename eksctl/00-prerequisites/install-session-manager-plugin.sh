#!/usr/bin/env bash
set -euo pipefail

if command -v session-manager-plugin >/dev/null 2>&1; then
  session-manager-plugin --version
  exit 0
fi

case "$(uname -s)" in
  Darwin)
    if command -v brew >/dev/null 2>&1; then
      brew install --cask session-manager-plugin
    else
      echo "Homebrew is required on macOS: https://brew.sh"
      exit 1
    fi
    ;;
  Linux)
    if [ -f /etc/os-release ]; then
      . /etc/os-release
    else
      echo "Cannot detect Linux distribution."
      exit 1
    fi
    ARCH="$(uname -m)"
    case "$ID" in
      amzn|rhel|centos|fedora)
        case "$ARCH" in
          x86_64) PKG_ARCH="64bit" ;;
          aarch64|arm64) PKG_ARCH="arm64" ;;
          *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
        esac
        curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_${PKG_ARCH}/session-manager-plugin.rpm" -o /tmp/session-manager-plugin.rpm
        sudo yum install -y /tmp/session-manager-plugin.rpm
        ;;
      ubuntu|debian)
        case "$ARCH" in
          x86_64) PKG_ARCH="64bit" ;;
          aarch64|arm64) PKG_ARCH="arm64" ;;
          *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
        esac
        curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_${PKG_ARCH}/session-manager-plugin.deb" -o /tmp/session-manager-plugin.deb
        sudo dpkg -i /tmp/session-manager-plugin.deb
        ;;
      *)
        echo "Unsupported Linux distribution: $ID"
        exit 1
        ;;
    esac
    ;;
  *)
    echo "Unsupported OS: $(uname -s)"
    exit 1
    ;;
esac

session-manager-plugin --version
