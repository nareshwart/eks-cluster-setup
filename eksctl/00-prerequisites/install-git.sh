#!/usr/bin/env bash
set -euo pipefail

if command -v git >/dev/null 2>&1; then
  git --version
  exit 0
fi

case "$(uname -s)" in
  Darwin)
    if command -v brew >/dev/null 2>&1; then
      brew install git
    else
      xcode-select --install
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
      amzn) sudo yum install -y git ;;
      ubuntu|debian) sudo apt-get update && sudo apt-get install -y git ;;
      *) echo "Unsupported Linux distribution: $ID"; exit 1 ;;
    esac
    ;;
  *)
    echo "Unsupported OS: $(uname -s)"
    exit 1
    ;;
esac

git --version
