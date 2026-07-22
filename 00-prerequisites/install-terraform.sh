#!/usr/bin/env bash
set -euo pipefail

if command -v terraform >/dev/null 2>&1; then
  terraform version
  exit 0
fi

case "$(uname -s)" in
  Darwin)
    if command -v brew >/dev/null 2>&1; then
      brew tap hashicorp/tap
      brew install hashicorp/tap/terraform
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
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
        sudo yum install -y terraform
        ;;
      ubuntu|debian)
        sudo apt-get update
        sudo apt-get install -y gnupg software-properties-common
        curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt-get update
        sudo apt-get install -y terraform
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

terraform version
