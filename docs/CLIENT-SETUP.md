# PrismLauncher `26.3` Client Optimization Setup

Configured PrismLauncher instance `~/.local/share/PrismLauncher/instances/26.3/` for maximum FPS and **512-chunk distant views** on **Intel Core i7-13650HX + NVIDIA GeForce RTX 4060 Laptop GPU (8 GiB VRAM) + 16 GiB RAM**.

## Instance & Hardware Tuning (`instance.cfg` & `mmc-pack.json`)

- **Loader:** Fabric `0.20.1` + Intermediary `26.3`
- **Java:** `java-runtime-epsilon` (`25.0.1`) with Generational ZGC (`-XX:+UseZGC -XX:+AlwaysPreTouch -XX:+DisableExplicitGC`)
- **Heap:** `MinMemAlloc=512`, `MaxMemAlloc=6144` (`6 GiB`)
- **GPU Offload:** `UseDiscreteGpu=true`, `OverridePerformance=true` (forces NVIDIA RTX 4060 instead of integrated Intel UHD Graphics)
- **Distant Views & Rendering Alignment:**
  - `config/voxy-config.json`: `enabled=true`, `enable_rendering=true`, `ingest_enabled=true`, `section_render_distance=16.0` (**512 chunks** in Voxy's UI)
  - `config/voxyworldgenv3.json`: `enabled=true`, `detailDistance=512`, `radius=128`
  - `config/bobby.conf`: `max-render-distance=32`, `no-block-entities=true`, `unload-delay-secs=60` (caches server chunks sent at `view-distance=10`)
  - `config/nvidium-config.json`: `enable_temporal_coherence=true`, `async_bfs=true`, `use_nv_fragment_shader_barycentric=true`
  - `config/sodium-options.json`: `use_no_error_g_l_context=true`, `animate_only_visible_textures=true`, `chunk_builder_threads=0`
  - `options.txt`: `enableVsync=false`, `maxFps=260` (uncapped), `entityShadows=false`, `biomeBlendRadius=1`, `particles=1`
- **Multiplayer Entry (`servers.dat`):** Pre-added `AWS Mumbai 26.3 Fabric SMP` (`43.204.157.116`)

## Installed FPS, Distant-View & QoL Mods (`59` JARs)

- **Distant Views & RTX Rendering:** `Sodium` (`0.9.2+mc26.3`), `Sodium Extra` (`0.9.5`), `Reese's Sodium Options` (`2.2.5`), `Voxy` (`0.2.20-beta`), `Voxy Extra` (`0.3.0+26.3`), `Voxy WorldGen` (`3.0.0`), `Nvidium` (`0.4.4-beta7-26.3`), `Bobby` (`5.2.16`), `Iris` (`1.11.7+mc26.3`), `ImmediatelyFast` (`1.17.1`), `EntityCulling` (`1.11.3`), `More Culling` (`1.9.1`), `Better Block Entities` (`1.4.0`), `Gnetum` (`4.6.4`), `Ixeris` (`4.6.11`), `BadOptimizations` (`2.4.1`), `Dynamic FPS` (`3.11.10`)
- **Engine & Memory:** `Fabric API` (`0.166.0`), `Lithium` (`0.26.3`), `FerriteCore` (`9.0.0`), `ModernFix` (`5.27.20-build.2`), `C2ME` (`0.4.2-alpha.0.116`), `ScalableLux` (`0.3.0-alpha.0.6`), `Krypton` (`0.3.2`), `FastQuit` (`3.1.5`), `Fast IP Ping` (`v1.0.12`)
- **QoL & Libraries:** `Mod Menu`, `Cloth Config`, `YACL`, `Fabric Language Kotlin`, `Placeholder API`, `Collective`, `TCDCommons`, `MaLiLib`, `Xaero's Minimap`, `Xaero's World Map`, `Litematica`, `Better Clouds`, `Better Statistics Screen`, `Skyboxify`, `EnchantmentHelper`, `Boat Item View`, `Quick Pack`, `Resourcify`, `MinecraftCapes`, `Freecam`, `Full Brightness Toggle`, `Gamma Utils`, `Zoomify`, `Shulker Box Tooltip`, `Mouse Tweaks`, `BetterF3`, `Continuity`, `Controlling`, `Searchables`, `Fadeless`, `ClientSort`, `PrickleMC`, `Crash Assistant`

> **Note on Sodium Version Pin:** `Voxy 0.2.20-beta`, `Nvidium 0.4.4-beta7-26.3`, and `Iris 1.11.7+mc26.3` all require `Sodium 0.9.2+mc26.3` (paired with `Sodium Extra 0.9.5`, `Reese's 2.2.5`, `BBE 1.4.0`, and `More Culling 1.9.1`).

## Copied & Updated Texture/Resource Packs (`11`) and Shaders (`5`)

- **Resource Packs (active in `options.txt`):** `Low Shield.zip`, `LowOnFire v26.1§8.zip`, `Unique Dark - Lite - 1.20.2-26.x.zip` (`2.9.1` for `26.3`), `NewGlowingOres-§6[Border]§r.zip`, `Dramatic Skys Demo 1.5.3.36.6.zip` (`26.3`), `SodiumTranslations.zip`, `Mod Menu Helper.zip`, plus `Default-Dark-Mode-26.3-2026.9.0.zip`, `Faithful 64x`, `Default HD 128x Demo`, `Default HD 512x Demo`
- **Shader Packs:** `BSL_v10.1.3.zip`, `ComplementaryReimagined_r5.7.1.zip`, `ComplementaryUnbound_r5.7.1.zip`, `photon_v1.3b.zip`, `Solas Shader V3.5.zip`
