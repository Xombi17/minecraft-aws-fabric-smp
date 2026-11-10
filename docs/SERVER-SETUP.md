# Server Setup & Optimization

## Runtime & Directory Structure

- **Java:** Amazon Corretto `25.0.5+10-LTS` (`java-25-amazon-corretto-headless`)
- **Minecraft:** Java Edition `26.3` (`world_version 5023`, `pack_version.data_major 121`)
- **Fabric:** Installer `1.1.2`, Fabric Loader `0.20.1`
- **OS Swap Safety Net:** `2 GiB` `/swapfile` with `vm.swappiness=10` (OOM protection while keeping active heap in physical RAM)

```text
/home/ec2-user/minecraft/
├── backups/                 # Compressed .tar.zst backups + .sha256 files
├── config/                  # Mod configs (ServerCore, C2ME, Lithium, Chunky, etc.)
├── libraries/               # Fabric & Minecraft libraries
├── logs/                    # latest.log + rotating gc.log
├── mods/                    # 17 verified 26.3 Fabric JARs
├── run/                     # Named pipe console.fifo for safe systemd/backup commands
├── scripts/
│   ├── backup.sh
│   ├── mc-cmd.sh
│   ├── mc-graceful-stop.sh
│   ├── mc-health.sh
│   └── mc-idle-monitor.py
├── world/                   # Fresh 26.3 world + 13 Vanilla Tweaks datapacks
├── eula.txt
├── fabric-installer.jar
├── fabric-server-launch.jar
├── jvm.conf
├── mods_manifest.json
├── server.jar
├── server.properties
└── start.sh
```

## JVM Tuning & GC Evaluation (`/home/ec2-user/minecraft/jvm.conf`)

Both Generational ZGC and tuned G1GC were benchmarked on `m7i-flex.large` (`5120M`–`5632M` heap):

- **Generational ZGC (`-XX:+UseZGC`):** GC pause phases measured **`0.009 ms` to `0.027 ms`** (sub-millisecond, zero tick impact).
- **G1GC (`-XX:+UseG1GC`):** Evacuation pauses measured **`12.8 ms` to `105.3 ms`** (>2 full 50 ms game ticks).

Active `jvm.conf` uses Generational ZGC with `5 GiB` heap (`5120M`) and `SoftMaxHeapSize=4608M`, leaving ~`2.6 GiB` of the `7.6 GiB` host RAM for OS, native/off-heap buffers, filesystem cache, and backups:

```bash
HEAP_MIN="5120M"
HEAP_MAX="5120M"
GC_FLAGS="-XX:+UseZGC -XX:SoftMaxHeapSize=4608M -XX:+AlwaysPreTouch -XX:+DisableExplicitGC"
EXTRA_FLAGS="-XX:+ExitOnOutOfMemoryError -Dfile.encoding=UTF-8"
```

## Key `server.properties` Settings

- `max-players=20`, `difficulty=easy`, `gamemode=survival`
- `view-distance=8`, `simulation-distance=6`
- `online-mode=true`, `enable-rcon=false`, `white-list=false`
- `pause-when-empty-seconds=60` (pauses world ticking 60s after empty, conserving CPU before idle shutdown)
- `sync-chunk-writes=true`, `use-native-transport=true`

## ServerCore Tuning (`config/servercore/config.yml`)

- `lobotomize-villagers.enabled: true` (`tick-interval: 20`)
- `dynamic.enabled: true` (`target-mspt: 35`, scaling `CHUNK_TICK_DISTANCE` / `SIMULATION_DISTANCE` / `MOBCAP_PERCENTAGE` / `VIEW_DISTANCE` down under heavy player load, capped at `server.properties` limits `8` / `6`)

## systemd Lifecycle & Idle Auto-Shutdown

- **`/etc/systemd/system/minecraft.service`:** Runs `start.sh` as `ec2-user`, auto-starts on EC2 boot, restarts on unexpected failures (`Restart=on-failure`), and runs `mc-graceful-stop.sh $MAINPID` (`save-all flush` + `stop`, `TimeoutStopSec=120`) via `run/console.fifo`.
- **`/etc/systemd/system/mc-idle-shutdown.service` + `/etc/default/mc-idle-shutdown`:**
  - Polls local Server List Ping (`127.0.0.1:25565`) and established `:25565` TCP sockets every `30s` (with `300s` boot grace).
  - After `1200s` (`20 minutes`) continuously at `0` players, sends `save-all flush`, stops `minecraft.service`, and runs `sudo poweroff` (EC2 transitions to `stopped`).
  - **Important:** Players cannot auto-wake a stopped EC2 instance by connecting in Minecraft; run `mc-server start` (or `mc-friend.sh start`) first.

## Local CLI (`/home/varad/Documents/mc-server.sh`)

- Symlinked to `~/.local/bin/mc-server`
- Config stored separately in `~/.config/mc-server/config.env`
- Handles `stopped`, `stopping`, `pending`, and `running` states cleanly, waits for SSH & port `25565` readiness without fixed sleep intervals, and waits for `stopped` before restarting.
