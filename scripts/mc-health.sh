#!/usr/bin/env bash
# Server monitoring & diagnostics helper (CPU, RAM, JVM heap, GC, disk, network, players, uptime).

set -euo pipefail

MC_DIR="/home/ec2-user/minecraft"

echo "=== System & Uptime ==="
uptime
echo ""

echo "=== Service Status ==="
systemctl is-active minecraft.service mc-idle-shutdown.service mc-backup.timer || true
MC_PID=$(systemctl show -p MainPID --value minecraft.service 2>/dev/null || echo "0")
echo "minecraft MainPID: ${MC_PID}"
echo ""

echo "=== Memory & Swap ==="
free -h
if [[ "${MC_PID:-0}" -gt 0 ]] && [[ -r "/proc/${MC_PID}/status" ]]; then
  grep -E "VmRSS|VmSize|Threads" "/proc/${MC_PID}/status" || true
fi
echo ""

echo "=== Disk Usage ==="
df -h / "$MC_DIR"
du -sh "${MC_DIR}/world" "${MC_DIR}/backups" "${MC_DIR}/mods" "${MC_DIR}/logs" 2>/dev/null || true
echo ""

echo "=== Player Count & Port 25565 ==="
python3 - << 'PYEOF'
import sys
sys.path.insert(0, "/home/ec2-user/minecraft/scripts")
try:
    import importlib.util
    spec = importlib.util.spec_from_file_location("idle", "/home/ec2-user/minecraft/scripts/mc-idle-monitor.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    cnt = mod.query_slp_player_count("127.0.0.1", 25565)
    tcp = mod.established_tcp_clients(25565)
    print(f"Online players (SLP): {cnt if cnt is not None else 'unavailable'} | Established TCP :25565: {tcp}")
except Exception as e:
    print(f"Player query failed: {e}")
PYEOF
echo ""

echo "=== Network RX/TX (since boot) ==="
ip -s link show dev "$(ip route show default | awk '/default/ {print $5; exit}')" | tail -n 4 || true
echo ""

echo "=== Recent GC Pauses (last 10) ==="
if [[ -f "${MC_DIR}/logs/gc.log" ]]; then
  grep -E "Pause|OutOfMemory" "${MC_DIR}/logs/gc.log" | tail -n 10 || echo "No pauses recorded yet"
else
  echo "No gc.log found"
fi
echo ""

echo "=== Recent Spark Reports ==="
grep -E "spark\.lucko\.me|TPS|MSPT" "${MC_DIR}/logs/latest.log" 2>/dev/null | tail -n 10 || true
