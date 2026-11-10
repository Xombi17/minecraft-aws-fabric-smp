#!/usr/bin/env bash
# Graceful stop helper used by systemd ExecStop to flush world saves before exit.

set -euo pipefail

MC_CMD="/home/ec2-user/minecraft/scripts/mc-cmd.sh"
PID="${1:-${MAINPID:-}}"

if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
  if "$MC_CMD" "save-all flush" 2>/dev/null; then
    sleep 3
    "$MC_CMD" "stop" 2>/dev/null || true
  else
    kill -TERM "$PID" 2>/dev/null || true
  fi

  # Wait up to 90s for JVM to flush chunks and exit cleanly
  for _ in $(seq 1 90); do
    if ! kill -0 "$PID" 2>/dev/null; then
      exit 0
    fi
    sleep 1
  done

  # Fallback SIGTERM if console stop hung
  kill -TERM "$PID" 2>/dev/null || true
  for _ in $(seq 1 20); do
    if ! kill -0 "$PID" 2>/dev/null; then
      exit 0
    fi
    sleep 1
  done
fi
