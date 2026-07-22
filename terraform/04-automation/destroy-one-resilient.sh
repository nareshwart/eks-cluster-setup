#!/usr/bin/env bash
# Destroy a single EKS cluster in a detached session so the destroy keeps
# running even if your SSH session to the jump box drops mid-way.
#
# Usage:
#   ./destroy-one-resilient.sh dev01            # start destroy, detached
#   ./destroy-one-resilient.sh dev01 --attach   # reattach to watch progress
#   ./destroy-one-resilient.sh dev01 --status   # check if still running
set -euo pipefail

CLUSTER="${1:?Usage: destroy-one-resilient.sh <cluster_name> [--attach|--status]}"
ACTION="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION="destroy-${CLUSTER}"
LOG_FILE="/tmp/terraform-destroy-${CLUSTER}.log"

if command -v tmux >/dev/null 2>&1; then
  case "${ACTION}" in
    --attach)
      tmux attach -t "${SESSION}"
      exit 0
      ;;
    --status)
      if tmux has-session -t "${SESSION}" 2>/dev/null; then
        echo "Still running. Attach with: $0 ${CLUSTER} --attach"
      else
        echo "Not running (finished, or never started). Log: ${LOG_FILE}"
      fi
      exit 0
      ;;
  esac

  if tmux has-session -t "${SESSION}" 2>/dev/null; then
    echo "A destroy session for ${CLUSTER} is already running."
    echo "Attach with: $0 ${CLUSTER} --attach"
    exit 1
  fi

  echo ">>> Starting destroy for ${CLUSTER} inside detached tmux session '${SESSION}'"
  tmux new-session -d -s "${SESSION}" \
    "'${SCRIPT_DIR}/destroy-one.sh' '${CLUSTER}' 2>&1 | tee '${LOG_FILE}'"

  echo "Started. This keeps running even if your SSH session disconnects."
  echo "  Reattach to watch:  $0 ${CLUSTER} --attach"
  echo "  Check progress:     $0 ${CLUSTER} --status"
  echo "  Tail the log:       tail -f ${LOG_FILE}"
else
  echo "tmux not found, falling back to nohup (process survives disconnect, but you can't reattach interactively)."
  case "${ACTION}" in
    --attach)
      echo "tmux isn't installed, so interactive reattach isn't available. Use: tail -f ${LOG_FILE}"
      exit 0
      ;;
    --status)
      if pgrep -f "destroy-one.sh ${CLUSTER}" >/dev/null; then
        echo "Still running. Tail the log: tail -f ${LOG_FILE}"
      else
        echo "Not running (finished, or never started). Log: ${LOG_FILE}"
      fi
      exit 0
      ;;
  esac

  nohup "${SCRIPT_DIR}/destroy-one.sh" "${CLUSTER}" > "${LOG_FILE}" 2>&1 &
  disown
  echo "Started in background (PID $!)."
  echo "  Check progress: $0 ${CLUSTER} --status"
  echo "  Tail the log:   tail -f ${LOG_FILE}"
fi
