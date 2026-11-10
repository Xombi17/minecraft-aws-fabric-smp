# Mod & Datapack Inventory (Minecraft 26.3 / Fabric 0.20.1)

All mods were downloaded directly from Modrinth and verified via SHA-512 against `/home/ec2-user/minecraft/mods_manifest.json`. All 18 JARs load server-side with **no client mods required** so new players can join with a vanilla `26.3` client (clients with `Voxy` + `Voxygen` additionally receive server-generated distant LOD terrain automatically).

## Installed Fabric 26.3 Mods (18 JARs)

| Mod | Version | Channel | Side (`server` / `client`) | Purpose | Source |
|---|---|---|---|---|---|
| Fabric API | `0.166.0+26.3` | Release | optional / optional | Core Fabric hooks (`26.3`) | [Modrinth](https://modrinth.com/mod/fabric-api) |
| Lithium | `mc26.3-0.26.3-fabric` | Release | optional / optional | General game logic, AI, physics optimization | [Modrinth](https://modrinth.com/mod/lithium) |
| FerriteCore | `9.0.0-fabric` | Release | optional / optional | Memory footprint reduction | [Modrinth](https://modrinth.com/mod/ferritecore) |
| Krypton | `0.3.2` | Release | optional / optional | Netty networking stack optimization | [Modrinth](https://modrinth.com/mod/krypton) |
| C2ME (Fabric) | `0.4.2-alpha.0.116+26.3` | Alpha | required / optional | Multi-threaded chunk generation & I/O | [Modrinth](https://modrinth.com/mod/c2me-fabric) |
| ScalableLux | `0.3.0-alpha.0.6+26.3` | Alpha | optional / optional | Multi-threaded lighting engine | [Modrinth](https://modrinth.com/mod/scalablelux) |
| ServerCore | `1.5.20+26.3` | Release | required / unsupported | Dynamic MSPT/view-dist scaling, villager lobotomy | [Modrinth](https://modrinth.com/mod/servercore) |
| VMP (Very Many Players) | `0.2.0+beta.7.238+26.3` | Alpha | required / optional | High player-count entity/chunk/packet scaling | [Modrinth](https://modrinth.com/mod/vmp-fabric) |
| Alternate Current | `mc26.3-1.9.0` | Release | required / unsupported | Fast, low-lag redstone dust updates | [Modrinth](https://modrinth.com/mod/alternate-current) |
| Debugify | `26.3.0.0` | Release | optional / optional | Vanilla bugfixes | [Modrinth](https://modrinth.com/mod/debugify) |
| Packet Fixer | `3.3.6` | Release | optional / optional | Fixes NBT/packet size edge cases | [Modrinth](https://modrinth.com/mod/packetfixer) |
| ModernFix | `5.27.20-build.2` | Release | optional / optional | Startup, memory & cache optimizations | [Modrinth](https://modrinth.com/mod/modernfix) |
| Clumps | `26.3.2` | Release | optional / optional | Merges XP orbs to reduce entity lag | [Modrinth](https://modrinth.com/mod/clumps) |
| Get It Together, Drops! | `v1.5.1` | Release | required / unsupported | Combines nearby dropped items | [Modrinth](https://modrinth.com/mod/getittogetherdrops) |
| Forge Config API Port | `v26.3.1` | Release | optional / optional | Required dependency for Get It Together, Drops! | [Modrinth](https://modrinth.com/mod/forge-config-api-port) |
| Spark | `1.10.187-fabric` | Release | optional / optional | CPU/heap/MSPT profiler | [Modrinth](https://modrinth.com/mod/spark) |
| Chunky | `1.5.66` | Release | optional / optional | Controlled chunk pre-generation | [Modrinth](https://modrinth.com/mod/chunky) |
| Voxygen | `3.0.0` | Release | required / optional | Server-side Voxy LOD worldgen & streaming (`radius: 512`, `threads: 1`) | [Modrinth](https://modrinth.com/mod/xT0lnNE9) |

### Excluded Mods / Compatibility Notes
- **VMP + Voxygen compatibility:** `/home/ec2-user/minecraft/config/vmp.properties` sets `use_optimized_entity_tracking=false` because VMP's `MixinThreadedAnvilChunkStorageEntityTracker` and Voxygen's `TrackedEntityMixin` both `@Redirect` `ChunkMap.isChunkTracked` inside `TrackedEntity.updatePlayer`.
- **Noisium (`NoisiumForked`):** Latest Modrinth build targets `26.2`; excluded until a verified `26.3` build releases.
- **Lootr / Trade Cycling / Distant Horizons:** Excluded for the fresh vanilla-client-compatible world (Lootr and Trade Cycling require client installs on Modrinth).
- **Moonrise:** Not installed (conflicts with C2ME/ScalableLux).

## Installed Vanilla Tweaks `26.3` Datapacks (13 Packs)

All packs were freshly generated from `vanillatweaks.net` for `MC 26.3` (`min_format`/`max_format` `[121, 0]`) in `/home/ec2-user/minecraft/world/datapacks/`:

- `anti ghast grief v1.1.18 (MC 26.3).zip`
- `armored elytra v2.0.12 (MC 26.3).zip`
- `chunk loaders v1.0.19 (MC 26.3).zip`
- `double shulker shells v1.3.18 (MC 26.3).zip`
- `fast leaf decay v2.0.23 (MC 26.3).zip`
- `graves v4.1.2 (MC 26.3).zip`
- `more mob heads v2.20.1 (MC 26.3).zip`
- `multiplayer sleep v2.6.18 (MC 26.3).zip`
- `nether portal coords v1.1.18 (MC 26.3).zip`
- `player head drops v1.1.18 (MC 26.3).zip`
- `silence mobs v1.2.12 (MC 26.3).zip`
- `timber v2.1.22 (MC 26.3).zip`
- `unlock all recipes v2.0.19 (MC 26.3).zip`
