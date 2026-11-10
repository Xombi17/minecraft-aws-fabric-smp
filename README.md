# AWS Minecraft Fabric SMP & Reusable Deployment Template

Complete infrastructure, runtime automation, local/friend management CLIs, client FPS optimization guide, and a modular deployment template for running a Fabric-modded Minecraft Java Edition SMP on AWS EC2 (`ap-south-1`).

## Repository Structure

```text
.
├── cli/
│   ├── mc-server.sh           # Admin lifecycle CLI (start, stop, restart, status, logs, connect, health, backup)
│   └── config.env.example     # Template for ~/.config/mc-server/config.env
├── docs/                      # Complete setup, architecture, cost, backup/restore & troubleshooting docs
├── friend-kit/
│   ├── mc-friend.sh           # Scoped IAM Role start/stop/status CLI for friends (no SSH key needed)
│   └── README-FOR-FRIENDS.md  # Friend setup guide
├── scripts/                   # EC2 server-side scripts (FIFO console, graceful stop, idle shutdown, zstd backups, health)
├── systemd/                   # systemd services & backup timer
└── template/                  # Reusable one-command provisioner for any AWS account & Minecraft version
    ├── deploy.sh              # Provisions AWS VPC/SG/EC2/EIP/IAM/Budget & bootstraps server
    ├── bootstrap-ec2.sh       # Installs Corretto Java, Fabric, mods, datapacks, ZGC/G1GC & systemd
    ├── resolve_mods.py        # Resolves Modrinth Fabric mods + required dependencies for target MC version
    ├── fetch_datapacks.py     # Fetches matching Vanilla Tweaks datapacks for target MC version
    ├── deploy.config.env.example
    ├── modpacks/              # Server TPS/memory & client RTX/Sodium mod lists
    └── datapacks/             # Vanilla Tweaks pack selections
```

## Quick Start: Reuse for a Future Minecraft Server

1. Copy the template config and edit your AWS profile, region, instance type, and Minecraft version:

```bash
cp template/deploy.config.env.example my-new-server.env
# Edit AWS_PROFILE, AWS_REGION, INSTANCE_TYPE, MC_VERSION, BUDGET_EMAIL, etc.
```

2. Preview resolved Java version, Fabric loader, compatible mods, and AWS config (`--dry-run` creates nothing):

```bash
./template/deploy.sh --config my-new-server.env --dry-run
```

3. Deploy end-to-end:

```bash
./template/deploy.sh --config my-new-server.env
```

4. Manage your server from any terminal:

```bash
mc-server status
mc-server start
mc-server stop
mc-server restart
mc-server logs
mc-server health
mc-server backup manual
```

## Current Live Deployment Summary (`26.3`)

- **EC2:** `m7i-flex.large` (`2 vCPU`, `8 GiB RAM`, Amazon Linux 2023, `30 GB gp3`, `ap-south-1`)
- **Stack:** Amazon Corretto `25.0.5`, Fabric Loader `0.20.1`, Minecraft `26.3`, Generational ZGC (`-Xms5120M -Xmx5120M`)
- **Cost Controls:** `20-minute` zero-player idle auto-shutdown (`save-all flush` -> `systemctl stop` -> `poweroff`) + `$25` AWS Budget alert
- **Docs:** See [docs/README.md](docs/README.md) for full runbooks, mod inventory, and cost estimates.
