#!/usr/bin/env bash
# ==============================================================================
# Remote EC2 bootstrap script (Amazon Linux 2023).
# Uploaded and executed by template/deploy.sh over SSH using env config in
# /tmp/mc-bootstrap.env.
# ==============================================================================

set -euo pipefail

# shellcheck disable=SC1091
source /tmp/mc-bootstrap.env

MC_DIR="/home/ec2-user/minecraft"
mkdir -p "${MC_DIR}"/{mods,config,world/datapacks,backups,logs,scripts,run}

echo "[1/7] Installing Amazon Corretto ${JAVA_VERSION} and server utilities..."
sudo dnf -q makecache
sudo dnf install -y "java-${JAVA_VERSION}-amazon-corretto-headless" jq htop tmux unzip tar gzip zstd
java -version

echo "[2/7] Configuring 2 GiB swap safety net (if absent)..."
if ! swapon --show | grep -q "/swapfile"; then
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab > /dev/null
  echo "vm.swappiness=10" | sudo tee /etc/sysctl.d/99-minecraft.conf > /dev/null
  sudo sysctl -p /etc/sysctl.d/99-minecraft.conf > /dev/null || true
fi

echo "[3/7] Installing Minecraft ${MC_VERSION} + Fabric Loader ${FABRIC_LOADER_VERSION}..."
cd "$MC_DIR"
curl -fsSL -o fabric-installer.jar "https://maven.fabricmc.net/net/fabricmc/fabric-installer/${FABRIC_INSTALLER_VERSION}/fabric-installer-${FABRIC_INSTALLER_VERSION}.jar"
java -jar fabric-installer.jar server -mcversion "${MC_VERSION}" -loader "${FABRIC_LOADER_VERSION}" -downloadMinecraft

echo "[4/7] Downloading SHA-512 verified Fabric ${MC_VERSION} mods..."
python3 /tmp/resolve_mods.py \
  --mc-version "${MC_VERSION}" \
  --mod-list /tmp/server-mods.txt \
  --manifest-out "${MC_DIR}/mods_manifest.json" \
  --download-dir "${MC_DIR}/mods" \
  --server-only

if [[ -f /tmp/vanillatweaks.json ]]; then
  echo "[4b/7] Fetching Vanilla Tweaks ${MC_VERSION} datapacks..."
  python3 /tmp/fetch_datapacks.py \
    --mc-version "${MC_VERSION}" \
    --config /tmp/vanillatweaks.json \
    --out-dir "${MC_DIR}/world/datapacks"
fi

echo "[5/7] Writing eula.txt, server.properties, jvm.conf, and start.sh..."
cat > "${MC_DIR}/eula.txt" << 'EOF'
eula=true
EOF

cat > "${MC_DIR}/server.properties" << EOF
accepts-transfers=false
allow-flight=false
broadcast-console-to-ops=true
broadcast-rcon-to-ops=true
difficulty=${MC_DIFFICULTY}
enable-code-of-conduct=false
enable-jmx-monitoring=false
enable-query=false
enable-rcon=false
enable-status=true
enforce-secure-profile=true
enforce-whitelist=${MC_WHITELIST}
entity-broadcast-range-percentage=100
force-gamemode=false
function-permission-level=2
gamemode=${MC_GAMEMODE}
generate-structures=true
generator-settings={}
hardcore=false
hide-online-players=false
level-name=world
level-seed=${MC_SEED}
level-type=minecraft\:normal
log-ips=true
max-chained-neighbor-updates=1000000
max-players=${MC_MAX_PLAYERS}
max-tick-time=60000
max-world-size=29999984
motd=${MC_MOTD}
network-compression-threshold=256
online-mode=true
op-permission-level=4
pause-when-empty-seconds=${MC_PAUSE_EMPTY_SECONDS}
player-idle-timeout=0
prevent-proxy-connections=false
query.port=25565
rate-limit=0
region-file-compression=deflate
require-resource-pack=false
server-ip=
server-port=25565
simulation-distance=${MC_SIM_DISTANCE}
spawn-protection=${MC_SPAWN_PROTECTION}
sync-chunk-writes=true
use-native-transport=true
view-distance=${MC_VIEW_DISTANCE}
white-list=${MC_WHITELIST}
EOF

# Determine heap allocation dynamically if HEAP_MB=auto
TOTAL_MEM_MB=$(awk '/MemTotal:/ {print int($2/1024)}' /proc/meminfo)
if [[ "${HEAP_MB}" == "auto" ]]; then
  if (( TOTAL_MEM_MB <= 9000 )); then
    COMPUTED_HEAP=$(( TOTAL_MEM_MB * 65 / 100 ))
  else
    COMPUTED_HEAP=$(( TOTAL_MEM_MB * 62 / 100 ))
    (( COMPUTED_HEAP > 12288 )) && COMPUTED_HEAP=12288
  fi
else
  COMPUTED_HEAP="${HEAP_MB}"
fi
SOFT_HEAP=$(( COMPUTED_HEAP * 90 / 100 ))

if [[ "${GC_MODE}" == "zgc" ]] && (( JAVA_VERSION >= 21 )); then
  if (( JAVA_VERSION >= 24 )); then
    GC_FLAGS="-XX:+UseZGC -XX:SoftMaxHeapSize=${SOFT_HEAP}M -XX:+AlwaysPreTouch -XX:+DisableExplicitGC"
  else
    GC_FLAGS="-XX:+UseZGC -XX:+ZGenerational -XX:SoftMaxHeapSize=${SOFT_HEAP}M -XX:+AlwaysPreTouch -XX:+DisableExplicitGC"
  fi
else
  GC_FLAGS="-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=50 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1"
fi

cat > "${MC_DIR}/jvm.conf" << EOF
# Auto-configured for ${TOTAL_MEM_MB} MiB host RAM (Java ${JAVA_VERSION}, GC=${GC_MODE})
HEAP_MIN="${COMPUTED_HEAP}M"
HEAP_MAX="${COMPUTED_HEAP}M"
GC_FLAGS="${GC_FLAGS}"
EXTRA_FLAGS="-XX:+ExitOnOutOfMemoryError -Dfile.encoding=UTF-8"
EOF

cat > "${MC_DIR}/start.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
MC_DIR="/home/ec2-user/minecraft"
cd "$MC_DIR"
# shellcheck disable=SC1091
source "${MC_DIR}/jvm.conf"
mkdir -p "${MC_DIR}/run" "${MC_DIR}/logs"
FIFO="${MC_DIR}/run/console.fifo"
rm -f "$FIFO"
mkfifo -m 600 "$FIFO"
exec 3<>"$FIFO"
exec 0<&3
read -r -a GC_ARR <<< "$GC_FLAGS"
read -r -a EXTRA_ARR <<< "$EXTRA_FLAGS"
exec java \
  "-Xms${HEAP_MIN}" \
  "-Xmx${HEAP_MAX}" \
  "${GC_ARR[@]}" \
  "${EXTRA_ARR[@]}" \
  "-Xlog:gc*:file=${MC_DIR}/logs/gc.log:time,uptime,level,tags:filecount=5,filesize=10M" \
  -jar "${MC_DIR}/fabric-server-launch.jar" nogui
EOF
chmod +x "${MC_DIR}/start.sh" "${MC_DIR}/scripts/"*.sh "${MC_DIR}/scripts/"*.py

# Write safe defaults for VMP + Voxygen (avoids TrackedEntityMixin @Redirect conflict and bounds worker threads)
cat > "${MC_DIR}/config/vmp.properties" << 'EOF'
use_optimized_entity_tracking=false
EOF

cat > "${MC_DIR}/config/voxyworldgenv3.json" << 'EOF'
{
  "enabled": true,
  "engine": "PIPELINE",
  "radius": 512,
  "threads": 1,
  "tileSize": 16,
  "msptLimit": 40,
  "lightMode": "ACCURATE",
  "ticketInflight": 64,
  "sendPerTick": 24,
  "threadPriority": 2,
  "horizonEnabled": false,
  "horizonDistanceK": 40,
  "horizonDetail": 100,
  "detailDistance": 512,
  "detailDecorate": false
}
EOF

echo "[6/7] Installing systemd units and initial world boot..."
sudo tee /etc/default/mc-idle-shutdown > /dev/null << EOF
IDLE_TIMEOUT_SECONDS=${IDLE_TIMEOUT_SECONDS}
CHECK_INTERVAL_SECONDS=${IDLE_CHECK_INTERVAL}
BOOT_GRACE_SECONDS=${IDLE_BOOT_GRACE}
DRY_RUN=0
EOF

sudo mv /tmp/minecraft.service /tmp/mc-idle-shutdown.service /tmp/mc-backup.service /tmp/mc-backup.timer /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/minecraft.service /etc/systemd/system/mc-idle-shutdown.service /etc/systemd/system/mc-backup.service /etc/systemd/system/mc-backup.timer
sudo systemctl daemon-reload
sudo systemctl enable minecraft.service mc-idle-shutdown.service mc-backup.timer
sudo systemctl start minecraft.service mc-idle-shutdown.service mc-backup.timer

for i in $(seq 1 45); do
  if journalctl -u minecraft --since "3 minutes ago" --no-pager | grep -q "Done ("; then
    echo "[7/7] Server booted cleanly at poll $i!"
    break
  fi
  sleep 2
done

# Apply ServerCore tuning if generated
if [[ -f "${MC_DIR}/config/servercore/config.yml" ]]; then
  python3 - << PYEOF
p = "${MC_DIR}/config/servercore/config.yml"
txt = open(p).read()
txt = txt.replace(
    "  lobotomize-villagers:\n    # Makes villagers tick less often if they are stuck in a 1x1 space.\n    enabled: false",
    "  lobotomize-villagers:\n    # Makes villagers tick less often if they are stuck in a 1x1 space.\n    enabled: true"
)
txt = txt.replace(
    "# Automatically modifies dynamic settings based on the server performance.\ndynamic:\n  # Enables dynamic performance checks.\n  enabled: false",
    "# Automatically modifies dynamic settings based on the server performance.\ndynamic:\n  # Enables dynamic performance checks.\n  enabled: true"
)
txt = txt.replace("    CHUNK_TICK_DISTANCE: 10", "    CHUNK_TICK_DISTANCE: ${MC_SIM_DISTANCE}")
txt = txt.replace("    - setting: 'CHUNK_TICK_DISTANCE'\n      max: 10", "    - setting: 'CHUNK_TICK_DISTANCE'\n      max: ${MC_SIM_DISTANCE}")
txt = txt.replace("    - setting: 'SIMULATION_DISTANCE'\n      max: 10", "    - setting: 'SIMULATION_DISTANCE'\n      max: ${MC_SIM_DISTANCE}")
txt = txt.replace("    - setting: 'VIEW_DISTANCE'\n      max: 10", "    - setting: 'VIEW_DISTANCE'\n      max: ${MC_VIEW_DISTANCE}")
open(p, "w").write(txt)
PYEOF
  "${MC_DIR}/scripts/mc-cmd.sh" "servercore reload" 2>/dev/null || true
fi

"${MC_DIR}/scripts/mc-health.sh"
rm -f /tmp/mc-bootstrap.env /tmp/resolve_mods.py /tmp/fetch_datapacks.py /tmp/server-mods.txt /tmp/vanillatweaks.json
