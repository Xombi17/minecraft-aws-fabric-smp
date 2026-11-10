#!/usr/bin/env bash
# ==============================================================================
#  mc-server.sh — Minecraft 26.3 Fabric SMP Lifecycle & Management CLI
#  Usage: mc-server <start|stop|restart|status|logs|connect|health|backup|help>
# ==============================================================================

set -euo pipefail

CONFIG_FILE="${MC_SERVER_CONFIG:-$HOME/.config/mc-server/config.env}"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

AWS_REGION="${AWS_REGION:-ap-south-1}"
AWS_PROFILE="${AWS_PROFILE:-default}"
INSTANCE_ID="${INSTANCE_ID:?INSTANCE_ID must be set in $CONFIG_FILE}"
SSH_KEY="${SSH_KEY:-$HOME/Documents/minecraft-26.3-key.pem}"
SSH_USER="${SSH_USER:-ec2-user}"
MC_PORT="${MC_PORT:-25565}"
MC_DIR="${MC_DIR:-/home/ec2-user/minecraft}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"
SSH_WAIT_TIMEOUT="${SSH_WAIT_TIMEOUT:-120}"
MC_WAIT_TIMEOUT="${MC_WAIT_TIMEOUT:-120}"
EC2_WAIT_TIMEOUT="${EC2_WAIT_TIMEOUT:-180}"

AWS_ARGS=(--region "$AWS_REGION")
if [[ -n "${AWS_PROFILE:-}" ]]; then
  AWS_ARGS+=(--profile "$AWS_PROFILE")
fi

SSH_OPTS=(
  -i "$SSH_KEY"
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=8
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=3
)

log()  { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
warn() { printf '[%s] [WARN] %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
die()  { printf '[%s] [ERROR] %s\n' "$(date '+%H:%M:%S')" "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" > /dev/null 2>&1 || die "Required command '$1' not found."
}

has_ssh_key() {
  [[ -n "${SSH_KEY:-}" && -f "$SSH_KEY" ]]
}

aws_ec2() {
  aws ec2 "$@" "${AWS_ARGS[@]}"
}

get_instance_info() {
  aws_ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].[State.Name,PublicIpAddress,InstanceType,LaunchTime]' \
    --output text
}

get_state() {
  aws_ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text
}

get_public_ip() {
  local ip
  ip=$(aws_ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)
  if [[ -z "$ip" || "$ip" == "None" ]]; then
    return 1
  fi
  printf '%s\n' "$ip"
}

wait_for_ec2_state() {
  local target="$1"
  local timeout="${2:-$EC2_WAIT_TIMEOUT}"
  local elapsed=0
  local state

  while (( elapsed <= timeout )); do
    state=$(get_state)
    log "  EC2 state: $state (target: $target)"
    if [[ "$state" == "$target" ]]; then
      return 0
    fi
    if [[ "$state" == "terminated" || "$state" == "shutting-down" ]]; then
      die "Instance $INSTANCE_ID is in terminal state '$state'."
    fi
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
  done
  die "Timed out after ${timeout}s waiting for instance $INSTANCE_ID to reach '$target' (last state: $state)."
}

wait_for_ssh() {
  local ip="$1"
  local elapsed=0
  log "Waiting for SSH readiness on ${ip}..."
  while (( elapsed <= SSH_WAIT_TIMEOUT )); do
    if ssh "${SSH_OPTS[@]}" -o BatchMode=yes "${SSH_USER}@${ip}" "true" 2>/dev/null; then
      log "  SSH ready."
      return 0
    fi
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
  done
  die "Timed out after ${SSH_WAIT_TIMEOUT}s waiting for SSH on ${ip}."
}

check_mc_slp() {
  local ip="$1"
  python3 - "$ip" "$MC_PORT" << 'PYEOF'
import json, socket, struct, sys

host = sys.argv[1]
port = int(sys.argv[2])

def pack_varint(v):
    b = bytearray()
    while True:
        p = v & 0x7F
        v >>= 7
        b.append(p | (0x80 if v else 0))
        if not v:
            return bytes(b)

def read_varint(s):
    n = 0
    for sh in range(0, 35, 7):
        c = s.recv(1)
        if not c:
            raise EOFError()
        n |= (c[0] & 0x7F) << sh
        if not (c[0] & 0x80):
            return n
    raise ValueError()

try:
    hb = host.encode()
    hs = b"\x00" + pack_varint(777) + pack_varint(len(hb)) + hb + struct.pack(">H", port) + b"\x01"
    with socket.create_connection((host, port), timeout=3.0) as s:
        s.settimeout(3.0)
        s.sendall(pack_varint(len(hs)) + hs + b"\x01\x00")
        _ = read_varint(s)
        if read_varint(s) != 0:
            sys.exit(1)
        l = read_varint(s)
        buf = bytearray()
        while len(buf) < l:
            ch = s.recv(l - len(buf))
            if not ch:
                sys.exit(1)
            buf.extend(ch)
        d = json.loads(buf.decode())
        ver = d.get("version", {}).get("name", "?")
        pl = d.get("players", {})
        print(f"online={pl.get('online', '?')}/{pl.get('max', '?')} version={ver}")
except Exception:
    sys.exit(1)
PYEOF
}

wait_for_mc_port() {
  local ip="$1"
  local elapsed=0
  log "Waiting for Minecraft server (${ip}:${MC_PORT}) to accept connections..."
  while (( elapsed <= MC_WAIT_TIMEOUT )); do
    local slp_out
    if slp_out=$(check_mc_slp "$ip" 2>/dev/null); then
      log "  Minecraft server ready (${slp_out})."
      return 0
    fi
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
  done
  die "Timed out after ${MC_WAIT_TIMEOUT}s waiting for Minecraft on ${ip}:${MC_PORT}."
}

run_ssh() {
  local ip="$1"
  shift
  has_ssh_key || die "SSH key not found: $SSH_KEY"
  chmod 400 "$SSH_KEY" 2>/dev/null || true
  ssh "${SSH_OPTS[@]}" -o BatchMode=yes "${SSH_USER}@${ip}" "$@"
}

cmd_start() {
  local state
  state=$(get_state)
  log "Current state of $INSTANCE_ID: $state"

  case "$state" in
    running)
      log "Instance is already running."
      ;;
    pending)
      log "Instance is already starting; waiting for 'running'..."
      wait_for_ec2_state "running"
      ;;
    stopping)
      log "Instance is currently stopping; waiting for 'stopped' before starting..."
      wait_for_ec2_state "stopped"
      log "Starting instance $INSTANCE_ID..."
      aws_ec2 start-instances --instance-ids "$INSTANCE_ID" > /dev/null
      wait_for_ec2_state "running"
      ;;
    stopped)
      log "Starting instance $INSTANCE_ID..."
      aws_ec2 start-instances --instance-ids "$INSTANCE_ID" > /dev/null
      wait_for_ec2_state "running"
      ;;
    *)
      die "Cannot start instance from state '$state'."
      ;;
  esac

  local ip
  ip=$(get_public_ip) || die "Instance is running but no public IP was returned."
  log "Public IP: $ip"

  if has_ssh_key; then
    chmod 400 "$SSH_KEY" 2>/dev/null || true
    if ssh "${SSH_OPTS[@]}" -o BatchMode=yes "${SSH_USER}@${ip}" "true" 2>/dev/null || wait_for_ssh "$ip"; then
      if ! run_ssh "$ip" "systemctl is-active --quiet minecraft.service"; then
        log "Starting minecraft.service via systemd..."
        run_ssh "$ip" "sudo systemctl start minecraft.service"
      fi
    fi
  fi

  wait_for_mc_port "$ip"
  log "Minecraft 26.3 server is UP! Connect at: ${ip}:${MC_PORT}"
}

cmd_stop() {
  local state
  state=$(get_state)
  log "Current state of $INSTANCE_ID: $state"

  case "$state" in
    stopped)
      log "Instance is already stopped."
      return 0
      ;;
    stopping)
      log "Instance is already stopping; waiting for 'stopped'..."
      wait_for_ec2_state "stopped"
      log "Instance is stopped."
      return 0
      ;;
    pending)
      log "Instance is pending; waiting for 'running' before graceful stop..."
      wait_for_ec2_state "running"
      ;;
    running)
      ;;
    *)
      die "Cannot stop instance from state '$state'."
      ;;
  esac

  local ip=""
  if ip=$(get_public_ip 2>/dev/null) && has_ssh_key; then
    chmod 400 "$SSH_KEY" 2>/dev/null || true
    log "Stopping minecraft.service gracefully via SSH ($ip)..."
    if ssh "${SSH_OPTS[@]}" -o BatchMode=yes "${SSH_USER}@${ip}" \
      "if systemctl is-active --quiet minecraft.service; then sudo systemctl stop minecraft.service; fi"; then
      log "Minecraft service stopped and world saved cleanly."
    else
      warn "SSH graceful stop failed (IP may not be in SG or SSH not ready); falling back to EC2 ACPI stop (systemd ExecStop will flush saves)."
    fi
  else
    log "Stopping EC2 instance (systemd ExecStop handles graceful world save on ACPI shutdown)..."
  fi

  log "Stopping EC2 instance $INSTANCE_ID..."
  aws_ec2 stop-instances --instance-ids "$INSTANCE_ID" > /dev/null
  wait_for_ec2_state "stopped"
  log "Instance $INSTANCE_ID is now STOPPED."
}

cmd_restart() {
  log "Restarting $INSTANCE_ID (stop -> wait stopped -> start)..."
  cmd_stop
  cmd_start
}

cmd_status() {
  local info state ip itype launch
  info=$(get_instance_info)
  read -r state ip itype launch <<< "$info"
  echo "Instance ID   : $INSTANCE_ID"
  echo "Region        : $AWS_REGION (profile: $AWS_PROFILE)"
  echo "Instance Type : $itype"
  echo "EC2 State     : $state"
  echo "Public IP     : ${ip:-none}"
  echo "Last Launch   : ${launch:-unknown}"

  if [[ "$state" == "running" && -n "${ip:-}" && "$ip" != "None" ]]; then
    local slp_out
    if slp_out=$(check_mc_slp "$ip" 2>/dev/null); then
      echo "Minecraft     : UP ($slp_out) -> ${ip}:${MC_PORT}"
    else
      echo "Minecraft     : Port ${MC_PORT} not responding yet"
    fi

    if has_ssh_key; then
      chmod 400 "$SSH_KEY" 2>/dev/null || true
      if ssh "${SSH_OPTS[@]}" -o BatchMode=yes "${SSH_USER}@${ip}" "true" 2>/dev/null; then
        local svc idle_svc
        svc=$(run_ssh "$ip" "systemctl is-active minecraft.service 2>/dev/null || true")
        idle_svc=$(run_ssh "$ip" "systemctl is-active mc-idle-shutdown.service 2>/dev/null || true")
        echo "systemd       : minecraft=${svc:-unknown}, mc-idle-shutdown=${idle_svc:-unknown}"
      else
        echo "SSH           : unreachable from current IP (check SG TCP/22 rule)"
      fi
    fi
  fi
}

cmd_logs() {
  local state ip
  state=$(get_state)
  [[ "$state" == "running" ]] || die "Instance is '$state' (must be running to view logs)."
  ip=$(get_public_ip) || die "Could not determine public IP."
  has_ssh_key || die "SSH key not found: $SSH_KEY"
  chmod 400 "$SSH_KEY" 2>/dev/null || true

  if [[ -t 1 ]]; then
    ssh "${SSH_OPTS[@]}" -t "${SSH_USER}@${ip}" "sudo journalctl -u minecraft -n 100 -f"
  else
    ssh "${SSH_OPTS[@]}" -o BatchMode=yes "${SSH_USER}@${ip}" "sudo journalctl -u minecraft -n 100 --no-pager"
  fi
}

cmd_connect() {
  local state ip
  state=$(get_state)
  [[ "$state" == "running" ]] || die "Instance is '$state' (must be running to connect)."
  ip=$(get_public_ip) || die "Could not determine public IP."
  has_ssh_key || die "SSH key not found: $SSH_KEY"
  chmod 400 "$SSH_KEY" 2>/dev/null || true
  exec ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}"
}

cmd_health() {
  local state ip
  state=$(get_state)
  [[ "$state" == "running" ]] || die "Instance is '$state' (must be running to check server health)."
  ip=$(get_public_ip) || die "Could not determine public IP."
  run_ssh "$ip" "${MC_DIR}/scripts/mc-health.sh"
}

cmd_backup() {
  local reason="${1:-manual}"
  local state ip
  state=$(get_state)
  [[ "$state" == "running" ]] || die "Instance is '$state' (must be running to trigger backup)."
  ip=$(get_public_ip) || die "Could not determine public IP."
  run_ssh "$ip" "${MC_DIR}/scripts/backup.sh" "$reason"
}

usage() {
  cat << EOF
Usage: $(basename "$0") <command>

Commands:
  start     Start EC2 instance (if needed), wait for SSH/MC, and print connect IP
  stop      Gracefully save & stop Minecraft, then stop EC2 and wait until stopped
  restart   Full stop (wait until stopped) followed by start
  status    Show EC2 state, public IP, live player count, and service status
  logs      Stream live Minecraft systemd journal logs via SSH
  connect   Open an interactive SSH session to the EC2 instance
  health    Run remote CPU, RAM, GC, disk, network, and player diagnostics
  backup    Trigger a compressed, SHA-256 verified backup (optional reason arg)
  help      Show this help message
EOF
}

require_cmd aws
require_cmd ssh
require_cmd python3

ACTION="${1:-help}"
case "$ACTION" in
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  restart) cmd_restart ;;
  status)  cmd_status ;;
  logs)    cmd_logs ;;
  connect) cmd_connect ;;
  health)  cmd_health ;;
  backup)  cmd_backup "${2:-manual}" ;;
  help|-h|--help) usage ;;
  *)
    warn "Unknown command: $ACTION"
    usage
    exit 2
    ;;
esac
