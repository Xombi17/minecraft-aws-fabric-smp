# PrismLauncher `26.3` Client Optimization Setup

Configured PrismLauncher instance `~/.local/share/PrismLauncher/instances/26.3/` for maximum FPS on **Intel Core i7-13650HX + NVIDIA GeForce RTX 4060 Laptop GPU (8 GiB VRAM) + 16 GiB RAM**.

## Instance & Hardware Tuning (`instance.cfg` & `mmc-pack.json`)

- **Loader:** Fabric `0.20.1` + Intermediary `26.3`
- **Java:** `java-runtime-epsilon` (`25.0.1`) with Generational ZGC (`-XX:+UseZGC -XX:+AlwaysPreTouch -XX:+DisableExplicitGC`)
- **Heap:** `MinMemAlloc=512`, `MaxMemAlloc=6144` (`6 GiB`)
- **GPU Offload:** `UseDiscreteGpu=true`, `OverridePerformance=true` (forces NVIDIA RTX 4060 instead of integrated Intel UHD Graphics)
- **Video & Rendering Tweaks:**
  - `options.txt`: `enableVsync=false`, `maxFps=260` (uncapped), `entityShadows=false`, `biomeBlendRadius=1`, `particles=1`
  - `config/nvidium-config.json`: `enable_temporal_coherence=true`, `async_bfs=true`, `use_nv_fragment_shader_barycentric=true`
  - `config/sodium-options.json`: `use_no_error_g_l_context=true`, `animate_only_visible_textures=true`, `chunk_builder_threads=0`
  - `config/bobby.conf`: `max-render-distance=32`, `no-block-entities=true`, `unload-delay-secs=60` (renders 16–32 cached chunks locally even with server `view-distance=8`)
- **Multiplayer Entry (`servers.dat`):** Pre-added `AWS Mumbai 26.3 Fabric SMP` (`43.204.157.116`)

## Installed FPS & QoL Mods (`42` JARs)

- **Rendering & FPS:** `Sodium` (`0.9.2+mc26.3`), `Sodium Extra` (`0.9.5`), `Reese's Sodium Options` (`2.2.5`), `Nvidium` (`0.4.4-beta7-26.3`), `Iris` (`1.11.7+mc26.3`), `ImmediatelyFast` (`1.17.1`), `EntityCulling` (`1.11.3`), `More Culling` (`1.9.1`), `Better Block Entities` (`1.4.0`), `Gnetum` (`4.6.4`), `Ixeris` (`4.6.11`), `BadOptimizations` (`2.4.1`), `Dynamic FPS` (`3.11.10`)
- **Engine, Memory & Chunk Caching:** `Fabric API` (`0.166.0`), `Lithium` (`0.26.3`), `FerriteCore` (`9.0.0`), `ModernFix` (`5.27.20-build.2`), `C2ME` (`0.4.2-alpha.0.116`), `ScalableLux` (`0.3.0-alpha.0.6`), `Krypton` (`0.3.2`), `Bobby` (`5.2.16`), `FastQuit` (`3.1.5`), `Fast IP Ping` (`v1.0.12`)
- **QoL & Libraries:** `Mod Menu`, `Cloth Config`, `YACL`, `Fabric Language Kotlin`, `Placeholder API`, `Xaero's Minimap`, `Xaero's World Map`, `Zoomify`, `Shulker Box Tooltip`, `Mouse Tweaks`, `BetterF3`, `Continuity`, `Controlling`, `Searchables`, `Gamma Utils`, `Fadeless`, `ClientSort`, `PrickleMC`, `Crash Assistant`

> **Note on Sodium Version Pin:** `Nvidium 0.4.4-beta7-26.3` and `Iris 1.11.7+mc26.3` specifically require `Sodium 0.9.2+mc26.3` (along with `Sodium Extra 0.9.5`, `Reese's 2.2.5`, `BBE 1.4.0`, and `More Culling 1.9.1`), so keep those pinned together unless Nvidium updates for `0.9.3`.

## Live Launch Verification

Tested via `prismlauncher --launch 26.3`: Fabric `0.20.1` loaded all 42 mods without dependency errors, initialized `NVIDIA GeForce RTX 4060 Laptop GPU/PCIe/SSE2` (`620.70.06`), enabled **Nvidium** and **ImmediatelyFast**, and reached the ready state (`Sound engine started`).
