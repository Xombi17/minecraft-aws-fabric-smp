#!/usr/bin/env bash
set -euo pipefail
FIFO="/home/ec2-user/minecraft/run/console.fifo"
if [[ ! -p "$FIFO" ]]; then
  echo "Console FIFO not found: $FIFO" >&2
  exit 1
fi
if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <minecraft-command>" >&2
  exit 1
fi
timeout 5 bash -c 'printf "%s\n" "$1" > "$2"' _ "$*" "$FIFO"
