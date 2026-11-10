#!/usr/bin/env python3
"""Idle-shutdown monitor for Minecraft 26.3 Fabric EC2 server.

Polls local Minecraft Server List Ping (127.0.0.1:25565) and established TCP
connections on port 25565. When zero players are connected continuously for
IDLE_TIMEOUT_SECONDS, flushes world saves, stops minecraft.service cleanly,
and invokes poweroff (EC2 InstanceInitiatedShutdownBehavior=stop).
"""

from __future__ import annotations

import json
import logging
import os
import socket
import struct
import subprocess
import sys
import time

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [mc-idle-monitor] %(levelname)s: %(message)s",
    stream=sys.stdout,
)
LOG = logging.getLogger("mc-idle-monitor")

MC_HOST = os.environ.get("MC_HOST", "127.0.0.1")
MC_PORT = int(os.environ.get("MC_PORT", "25565"))
CHECK_INTERVAL = int(os.environ.get("CHECK_INTERVAL_SECONDS", "30"))
IDLE_TIMEOUT = int(os.environ.get("IDLE_TIMEOUT_SECONDS", "1200"))  # 20 minutes
BOOT_GRACE = int(os.environ.get("BOOT_GRACE_SECONDS", "300"))      # 5 min boot grace
MC_CMD = os.environ.get("MC_CMD_PATH", "/home/ec2-user/minecraft/scripts/mc-cmd.sh")
DRY_RUN = os.environ.get("DRY_RUN", "0") == "1"


def pack_varint(val: int) -> bytes:
    out = bytearray()
    while True:
        part = val & 0x7F
        val >>= 7
        if val:
            out.append(part | 0x80)
        else:
            out.append(part)
            break
    return bytes(out)


def read_varint(sock: socket.socket) -> int:
    num = 0
    for shift in range(0, 35, 7):
        b = sock.recv(1)
        if not b:
            raise EOFError("Unexpected EOF reading VarInt")
        byte = b[0]
        num |= (byte & 0x7F) << shift
        if not (byte & 0x80):
            return num
    raise ValueError("VarInt too big")


def recv_exact(sock: socket.socket, length: int) -> bytes:
    buf = bytearray()
    while len(buf) < length:
        chunk = sock.recv(length - len(buf))
        if not chunk:
            raise EOFError("Unexpected EOF reading payload")
        buf.extend(chunk)
    return bytes(buf)


def query_slp_player_count(host: str, port: int, timeout: float = 4.0) -> int | None:
    """Query Minecraft Server List Ping (SLP) and return online player count, or None on error."""
    host_bytes = host.encode("utf-8")
    handshake_payload = (
        b"\x00"
        + pack_varint(777)  # MC 26.3 protocol version
        + pack_varint(len(host_bytes))
        + host_bytes
        + struct.pack(">H", port)
        + b"\x01"  # status state
    )
    handshake_packet = pack_varint(len(handshake_payload)) + handshake_payload
    status_request = b"\x01\x00"

    try:
        with socket.create_connection((host, port), timeout=timeout) as sock:
            sock.settimeout(timeout)
            sock.sendall(handshake_packet + status_request)
            _pkt_len = read_varint(sock)
            pkt_id = read_varint(sock)
            if pkt_id != 0:
                return None
            json_len = read_varint(sock)
            raw = recv_exact(sock, json_len)
            data = json.loads(raw.decode("utf-8"))
            return int(data["players"]["online"])
    except Exception as exc:
        LOG.debug("SLP query failed: %s", exc)
        return None


def established_tcp_clients(port: int) -> int:
    """Return count of established TCP connections on the Minecraft server port."""
    try:
        out = subprocess.check_output(
            ["ss", "-Htn", "state", "established", f"( sport = :{port} )"],
            text=True,
            timeout=5,
        )
        return len([ln for ln in out.splitlines() if ln.strip()])
    except Exception:
        return 0


def service_is_active(unit: str = "minecraft.service") -> bool:
    res = subprocess.run(
        ["systemctl", "is-active", "--quiet", unit],
        timeout=5,
    )
    return res.returncode == 0


def chunky_task_active(log_path: str = "/home/ec2-user/minecraft/logs/latest.log") -> bool:
    """Return True if Chunky appears to be actively pre-generating chunks."""
    try:
        if not os.path.exists(log_path) or (time.time() - os.path.getmtime(log_path)) > 60:
            return False
        with open(log_path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - 8192))
            tail = f.read().decode("utf-8", errors="replace").splitlines()[-20:]
        for line in reversed(tail):
            if "[Chunky] Task finished" in line or "[Chunky] Task cancelled" in line or "[Chunky] Task paused" in line:
                return False
            if "[Chunky] Task running" in line or "[Chunky] Task started" in line:
                return True
    except Exception:
        return False
    return False


def system_uptime_seconds() -> float:
    with open("/proc/uptime", "r", encoding="utf-8") as f:
        return float(f.read().split()[0])


def perform_shutdown() -> None:
    LOG.info("Idle timeout reached with 0 players. Flushing world save and shutting down...")
    if os.path.exists(MC_CMD):
        subprocess.run([MC_CMD, "save-all flush"], check=False, timeout=10)
        time.sleep(5)

    if DRY_RUN:
        LOG.info("DRY_RUN=1 set; skipping systemctl stop and poweroff.")
        return

    subprocess.run(["sudo", "systemctl", "stop", "minecraft.service"], check=False, timeout=130)
    LOG.info("minecraft.service stopped cleanly. Calling sudo poweroff...")
    subprocess.run(["sudo", "poweroff"], check=False, timeout=15)


def main() -> None:
    LOG.info(
        "Started (host=%s:%d, check=%ds, idle_timeout=%ds, boot_grace=%ds, dry_run=%s)",
        MC_HOST, MC_PORT, CHECK_INTERVAL, IDLE_TIMEOUT, BOOT_GRACE, DRY_RUN,
    )
    idle_since: float | None = None

    while True:
        time.sleep(CHECK_INTERVAL)

        if system_uptime_seconds() < BOOT_GRACE:
            LOG.debug("Within boot grace period; skipping idle accumulation.")
            continue

        if not service_is_active("minecraft.service"):
            # Do not shut down EC2 if admin intentionally stopped minecraft.service for maintenance,
            # unless it stays idle? Actually wait: if minecraft isn't active, reset timer so
            # manual maintenance isn't interrupted abruptly.
            idle_since = None
            continue

        slp_players = query_slp_player_count(MC_HOST, MC_PORT)
        tcp_clients = established_tcp_clients(MC_PORT)

        if slp_players is None:
            # Server may still be starting up or saving; reset idle timer to stay safe.
            LOG.warning("SLP status unavailable (server starting/busy); resetting idle timer.")
            idle_since = None
            continue

        if slp_players > 0 or tcp_clients > 0:
            if idle_since is not None:
                LOG.info("Player activity detected (slp=%d, tcp=%d); resetting idle timer.", slp_players, tcp_clients)
            idle_since = None
            continue

        if chunky_task_active():
            if idle_since is not None:
                LOG.info("Active Chunky pre-generation detected; pausing idle shutdown timer.")
            idle_since = None
            continue

        now = time.monotonic()
        if idle_since is None:
            idle_since = now
            LOG.info("0 players online. Starting %ds idle shutdown countdown.", IDLE_TIMEOUT)
            continue

        elapsed = now - idle_since
        remaining = max(0, int(IDLE_TIMEOUT - elapsed))
        if elapsed >= IDLE_TIMEOUT:
            # Double-check immediately before shutting down
            if (query_slp_player_count(MC_HOST, MC_PORT) or 0) == 0 and established_tcp_clients(MC_PORT) == 0:
                perform_shutdown()
                if DRY_RUN:
                    idle_since = None
                else:
                    break
            else:
                idle_since = None
        else:
            LOG.info("Server idle for %ds / %ds (%ds remaining).", int(elapsed), IDLE_TIMEOUT, remaining)


if __name__ == "__main__":
    main()
