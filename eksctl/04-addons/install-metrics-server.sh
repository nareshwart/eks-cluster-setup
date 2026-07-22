#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl rollout status deployment/metrics-server -n kube-system
kubectl top nodes || true
