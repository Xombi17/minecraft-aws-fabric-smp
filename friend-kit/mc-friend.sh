#!/usr/bin/env bash
# ==============================================================================
#  mc-friend.sh — Friend-Safe Minecraft 26.3 Server Launcher (No SSH Required)
#  Uses restricted IAM Role (MinecraftServerOperatorRole) to start/stop/check
#  only the Minecraft EC2 instance i-005bf9e3f493f2118 in ap-south-1.
# ==============================================================================

set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-mc-friend}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
INSTANCE_ID="${INSTANCE_ID:-i-005bf9e3f493f2118}"
SERVER_ADDR="${SERVER_ADDR:-43.204.157.116}"
MC_PORT="${MC_PORT:-25565}"
POLL_INTERVAL=5

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
die() { printf '[%s] [ERROR] %s\n' "$(date '+%H:%M:%S')" "$*" >&2; exit 1; }

command -v aws >/dev/null 2>&1 || die "Install AWS CLI v2 first."

get_state() {
  aws ec2 describe-instances \
    --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].State.Name' --output text
}

wait_state() {
  local target="$1"
  local s
  for _ in $(seq 1 36); do
    s=$(get_state)
    log "  EC2 state: $s (target: $target)"
    [[ "$s" == "$target" ]] && return 0
    sleep "$POLL_INTERVAL"
  done
  die "Timed out waiting for state $target"
}

check_mc_port() {
  if command -v nc >/dev/null 2>&1; then
    nc -z -w 2 "$SERVER_ADDR" "$MC_PORT" >/dev/null 2>&1
  else
    timeout 2 bash -c "</dev/tcp/${SERVER_ADDR}/${MC_PORT}" >/dev/null 2>&1
  fi
}

case "${1:-status}" in
  start)
    STATE=$(get_state)
    log "Current state: $STATE"
    if [[ "$STATE" == "stopping" ]]; then
      wait_state "stopped"
      STATE="stopped"
    fi
    if [[ "$STATE" == "stopped" ]]; then
      aws ec2 start-instances --region "$AWS_REGION" --profile "$AWS_PROFILE" --instance-ids "$INSTANCE_ID" >/dev/null
      wait_state "running"
    elif [[ "$STATE" == "pending" ]]; then
      wait_state "running"
    fi
    log "Waiting for Minecraft server to finish booting on ${SERVER_ADDR}:${MC_PORT}..."
    for _ in $(seq 1 30); do
      if check_mc_port; then
        log "Server is UP! Join in Minecraft 26.3 at: ${SERVER_ADDR}:${MC_PORT}"
        exit 0
      fi
      sleep 4
    done
    die "EC2 is running, but Minecraft did not open port ${MC_PORT} in time."
    ;;
  stop)
    STATE=$(get_state)
    log "Current state: $STATE"
    if [[ "$STATE" == "stopped" ]]; then
      log "Server is already stopped."
      exit 0
    fi
    aws ec2 stop-instances --region "$AWS_REGION" --profile "$AWS_PROFILE" --instance-ids "$INSTANCE_ID" >/dev/null
    wait_state "stopped"
    log "Server stopped cleanly."
    ;;
  status)
    STATE=$(get_state)
    echo "EC2 State : $STATE"
    echo "Address   : ${SERVER_ADDR}:${MC_PORT}"
    if [[ "$STATE" == "running" ]] && check_mc_port; then
      echo "Minecraft : ONLINE (ready to join)"
    elif [[ "$STATE" == "running" ]]; then
      echo "Minecraft : Booting..."
    else
      echo "Minecraft : OFFLINE (run './mc-friend.sh start' to boot)"
    fi
    ;;
  *)
    echo "Usage: $0 {start|stop|status}"
    exit 2
    ;;
esac
