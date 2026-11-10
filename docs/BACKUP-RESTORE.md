# Backup & Restore Guide

## Automated Backup Architecture

- **Script:** `/home/ec2-user/minecraft/scripts/backup.sh`
- **Schedule:** `mc-backup.timer` runs every `6 hours` (`00:00, 06:00, 12:00, 18:00 UTC`) when EC2 is running (`Persistent=false`, so booting an idle-stopped server does not immediately spike CPU with a catch-up backup).
- **Backup Contents:** `world/`, `server.properties`, `ops.json`, `whitelist.json`, `banned-ips.json`, `banned-players.json`, `config/`, `jvm.conf`, `mods_manifest.json`.
- **Format & Verification:**
  - Compressed with `zstd -T2 -6` (`mc-backup-<reason>-<UTC-timestamp>.tar.zst`)
  - Safely runs `save-off` -> `save-all flush` -> `tar | zstd` -> `save-on` (via `EXIT` trap so `save-on` is always restored)
  - Verifies archive integrity (`zstd -t` + `tar -tf`) and writes `<archive>.sha256`
- **Retention Policy:**
  - Keeps the latest **`7` `scheduled` backups** automatically.
  - **`manual`, `pre-upgrade`, and `pre-mod-change` backups are never auto-pruned**, ensuring the last known-good safety backup is never overwritten.

## Creating Manual / Pre-Change Backups

Always run before upgrading Minecraft, adding/removing mods, or changing configs:

```bash
mc-server backup pre-mod-change
# or: mc-server backup pre-upgrade
# or: mc-server backup manual
```

## Restoring a Backup

1. Connect to the server and verify available backups + checksums:

```bash
mc-server connect
cd /home/ec2-user/minecraft/backups
ls -lh
sha256sum -c mc-backup-manual-YYYYMMDD-HHMMSSZ.tar.zst.sha256
```

2. Stop the Minecraft service cleanly (leave EC2 running):

```bash
sudo systemctl stop minecraft.service
```

3. Move the current `world/` aside as a safety fallback (never delete the only working copy before testing restore):

```bash
cd /home/ec2-user/minecraft
mv world world.pre-restore.$(date +%Y%m%d-%H%M%S)
```

4. Extract the verified backup into `/home/ec2-user/minecraft`:

```bash
tar --use-compress-program=zstd -xf /home/ec2-user/minecraft/backups/<BACKUP_FILE>.tar.zst -C /home/ec2-user/minecraft
```

5. Start Minecraft and verify logs:

```bash
sudo systemctl start minecraft.service
journalctl -u minecraft -n 100 -f
```

6. Once confirmed working in-game, remove the old `world.pre-restore.*` folder to reclaim disk space.

## Copying a Backup Off-EC2 (Optional)

```bash
scp -i ~/Documents/minecraft-26.3-key.pem ec2-user@43.204.157.116:/home/ec2-user/minecraft/backups/<BACKUP_FILE>.tar.zst* ~/Documents/
```
