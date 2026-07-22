#!/usr/bin/env bash
set -euo pipefail

if command -v docker >/dev/null 2>&1; then
  docker --version
  exit 0
fi

case "$(uname -s)" in
  Darwin)
    if command -v brew >/dev/null 2>&1; then
      brew install --cask docker
      echo "Docker Desktop installed. Start Docker Desktop before using docker."
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
    case "$ID" in
      amzn)
        sudo yum install -y docker
        sudo systemctl enable --now docker
        sudo usermod -aG docker "$USER"
        ;;
      ubuntu|debian)
        sudo apt-get update
        sudo apt-get install -y docker.io
        sudo systemctl enable --now docker
        sudo usermod -aG docker "$USER"
        ;;
      *)
        echo "Unsupported Linux distribution: $ID"
        exit 1
        ;;
    esac
    echo "Log out and back in for docker group membership to take effect."
    ;;
  *)
    echo "Unsupported OS: $(uname -s)"
    exit 1
    ;;
esac
