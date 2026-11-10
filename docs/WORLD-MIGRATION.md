# World Migration Report & Chunky Pre-Generation Guide

## Legacy Backup Inspection (`1.21.11`)

- **Archive:** `/home/varad/minecraft-world-backup.tar.gz` (`2.76 GiB` compressed, `4.09 GiB` uncompressed)
- **SHA-256:** `65df42496306d3c1b1972b5d04b7239ea9a8b523ec16214f6cb6e73736f2f4dc` (verified match, `gzip -t` OK)
- **Staging Copy (Read-Only):** `/home/varad/mc-staging/old-1.21.11/` (original backup was never modified)
- **Contents Found:**
  - `1.21.11` (`DataVersion 4671`), Fabric Loader `0.18.6`, seed `7420605242600336383`
  - `22` mod JARs (including `DistantHorizons`, `Lootr`, `Trade Cycling`, `Unlimited Trading`, `VMP`, `Alternate Current`, `ModernFix`, `Noisium`)
  - `world/` (`4.0 GiB`): `region` `2.5 GiB`, `DIM1` `782 MiB`, `DIM-1` `344 MiB`, `DistantHorizons.sqlite` (`241 MiB`), and **19,133 Lootr files** (`world/data/lootr/`)
  - `14` datapacks (`12` Vanilla Tweaks capped at `pack_format 94`, plus `InfinityVault_UNIVERSAL.zip` and `Harvest Simplified 1.1.zip`)

## Production World Decision

Per project decision, **no legacy world data was migrated**. The `26.3` server runs a **brand-new `26.3` survival world** (`world/`, `DataVersion 5023`) for new players with fresh Vanilla Tweaks `26.3` datapacks (`data_major 121`). The original `/home/varad/minecraft-world-backup.tar.gz` and staged extraction remain intact locally if you ever want to inspect or extract anything later.

---

## Chunky Pre-Generation Guide (On-Demand — Not Auto-Started)

### Block Radius vs. Chunk Radius
Chunky's `/chunky radius <R>` takes **blocks**, **not chunks**:
- `1 chunk` = `16 × 16` blocks
- Total chunks in a square of block radius `R` = `(2R / 16)^2 = (R / 8)^2`
- In the old server's `config/chunky/tasks/minecraft/overworld.properties`, `radius=3000.0` was **3,000 blocks** (`187.5` chunks radius = `142,078` chunks, taking ~23 min before cancellation). An actual 3,000-*chunk* radius would be `48,000` blocks (`36,000,000` chunks), which would exceed a 30 GB disk by orders of magnitude.

### Recommended Pre-Generation Options (`m7i-flex.large`, 2 vCPU, 30 GB gp3)

| Option | Overworld Radius (Blocks / Chunks) | Approx. Total Chunks | Est. Disk Size | Est. Generation Time |
|---|---|---|---|---|
| **Small (Recommended Start)** | `1,500` blocks (`~94` chunks) | `~35,200` chunks | `~0.4–0.7 GiB` | `~6–10 min` |
| Medium | `2,500` blocks (`~156` chunks) | `~97,600` chunks | `~1.1–1.8 GiB` | `~18–30 min` |
| Previous Old Setting | `3,000` blocks (`~188` chunks) | `~140,625` chunks | `~1.6–2.6 GiB` | `~25–45 min` |

### How to Run Chunky When Ready (Only After Choosing Your Radius)

Run via SSH (`mc-server connect` -> `/home/ec2-user/minecraft/scripts/mc-cmd.sh`) while players are offline:

```bash
/home/ec2-user/minecraft/scripts/mc-cmd.sh "chunky world minecraft:overworld"
/home/ec2-user/minecraft/scripts/mc-cmd.sh "chunky center 0 0"
/home/ec2-user/minecraft/scripts/mc-cmd.sh "chunky radius 1500"
/home/ec2-user/minecraft/scripts/mc-cmd.sh "chunky start"
```

Pause/cancel anytime with `chunky pause` or `chunky cancel`, and monitor CPU/disk via `mc-server health` and `mc-server logs`.
