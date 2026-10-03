# BetterBrainer 1.0.2 release record

- Date: 2026-10-04.
- Authoritative source: `mods/active/BetterBrainer/`; Standard profile, ModID `BetterBrainer`, unchanged manifest paths and empty package list.
- Repository: https://github.com/Vansinnet/BetterBrainer; branch `main`, tag `v1.0.2`.
- Build command: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/release-mod.ps1 -Mod BetterBrainer -OutputDirectory releases/BetterBrainer-v1.0.2`.
- Validation: zero LuaLS diagnostics across all nine runtime Lua files; all nine Lua files plus the manifest load in LuaJIT and pass secondary Lua 5.5 syntax validation.
- Archive: `releases/BetterBrainer-v1.0.2/BetterBrainer.zip`.
- SHA-256: `EB1B3B26A4BE946A6806331CDE4FCEABE69FC42306C42A46312ED20B3CB9D3DF`.
- Source manifest: `releases/BetterBrainer-v1.0.2/BetterBrainer.source.sha256`; archive hash record: `releases/BetterBrainer-v1.0.2/BetterBrainer.zip.sha256`.
- Inspected payload: one `BetterBrainer/` root, `.mod`, nine runtime Lua files, `README.md`, `LICENSE` (12 files), all forward-slash paths. Tests, analysis, historical testing/changelog/publishing records, Git metadata/workflow, artwork and workspace tools are excluded.
- Source-facing hooks verified against 1.13.0 source; narrow deferred evidence recorded in workspace `types/CONTRACTS.md`. No LuaCATS/runtime metadata ships.
- Offline acceptance: 73/73 focused LuaJIT checks passed during implementation, including native-source full solves with zero mistakes. Runtime code has not changed since that pass.
- In-game acceptance: user reports that all speed changes work. Exact build, mission, server role, RTT, speeds, lifecycle coverage and measured timings were not recorded; no stronger context-specific result is claimed.
- User settings, options and translations are unchanged. Existing release v1.0.1 remains the rollback download; source before this release is commit `b5733668a9f5ea0fae0f05a3118c76e05888635e`.
- Release assets are built by the canonical local wrapper and uploaded with `gh`, rather than triggering a separate CI package rebuild.
