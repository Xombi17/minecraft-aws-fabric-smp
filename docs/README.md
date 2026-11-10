# Minecraft 26.3 Fabric SMP — Operations Guide

Production Fabric `26.3` Survival Multiplayer server deployed on AWS `ap-south-1` (Mumbai) with automated backups, idle EC2 auto-shutdown, and one-command local & friend management CLIs.

## Quick Summary

| Component | Value |
|---|---|
| AWS Account / Region | `097690245219` (`FREE` Plan) / `ap-south-1` (Mumbai) |
| EC2 Instance | `i-005bf9e3f493f2118` (`m7i-flex.large`, 2 vCPU, 8 GiB RAM, x86_64) |
| Public Address (Elastic IP) | `43.204.157.116:25565` (`eipalloc-0e8c03234120d16c2`) |
| OS / Java | Amazon Linux 2023 / Amazon Corretto `25.0.5+10-LTS` |
| Server Software | Minecraft `26.3` + Fabric Loader `0.20.1` (`fabric-server-launch.jar`) |
| World Mode | Fresh `26.3` Survival world (`white-list=false`, `difficulty=easy`) |
| Datapacks | 13 Vanilla Tweaks `26.3` datapacks (`data_major 121`) |
| Idle Auto-Shutdown | 20 minutes at `0` players -> `save-all flush` -> `systemctl stop` -> `poweroff` |

## Daily Commands

From any local terminal (`mc-server` symlinked to `~/.local/bin/mc-server`):

```bash
mc-server status    # EC2 state, Elastic IP, live player count, systemd state
mc-server start     # Boot EC2, wait for SSH + port 25565, print IP
mc-server stop      # Gracefully save & stop Minecraft, then stop EC2
mc-server restart   # Stop -> wait until stopped -> start
mc-server logs      # Stream live systemd journal logs
mc-server connect   # Open interactive SSH session
mc-server health    # CPU, RAM, GC pauses, disk, network, players
mc-server backup    # Trigger manual compressed + SHA-256 verified backup
```

## Documentation Index

- [AWS-INFRASTRUCTURE.md](AWS-INFRASTRUCTURE.md) — VPC, Security Group, EC2, EBS, Elastic IP, IAM Role/User, Budget
- [SERVER-SETUP.md](SERVER-SETUP.md) — Java 25, Fabric, JVM ZGC tuning, `server.properties`, `systemd`, idle shutdown
- [CLIENT-SETUP.md](CLIENT-SETUP.md) — PrismLauncher `26.3` RTX 4060 optimization (Sodium, Nvidium, Iris, 42 mods)
- [MOD-INVENTORY.md](MOD-INVENTORY.md) — Verified `26.3` Fabric mods (17 JARs) and Vanilla Tweaks `26.3` datapacks (13 packs)
- [WORLD-MIGRATION.md](WORLD-MIGRATION.md) — Inspection of legacy `1.21.11` backup, compatibility findings, and fresh-world decision
- [BACKUP-RESTORE.md](BACKUP-RESTORE.md) — Automated `zstd` backups, retention policy, and step-by-step restore procedure
- [COST-ESTIMATE.md](COST-ESTIMATE.md) — Mumbai (`ap-south-1`) pricing breakdown, credit burn, and cost optimization
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — Lag diagnostics (Spark/GC), SSH/SG updates, idle-shutdown & recovery runbooks
