## Faster autosolvers

- **Frequency:** removes the fixed 0.5-second opening delay at speed 5. Intermediate speeds also start sooner; speed 1 retains its original pacing.
- **Decode Search:** submits on the first fully confirmed target sample after movement at speed 5, saving one input frame.
- **Decode Symbols:** skips the 120 ms stability wait when a complete fresh board has arrived, retaining the initial button release and 30 ms safe hit margin.
- **Auto-scan:** after an interrupted scan, a different eligible target can start immediately when normal scan mode resumes. Same-target retry protection remains.

Native Drill search/transition times, Balance objective duration, scan confirmation time, settings and translations are unchanged.

## Installation

Download **BetterBrainer.zip** below and extract the `BetterBrainer` folder into your Darktide mods directory. Keep `BetterBrainer` enabled in `mod_load_order.txt`. Do not enable NoBrainer and BetterBrainer together.

## Verification

- User-tested in game: reported working for all changes. Exact mission, build, RTT and lifecycle coverage were not recorded.
- 73/73 focused offline LuaJIT checks passed against Darktide 1.13.0 Lua source, including complete simulated solves with zero mistakes.
- Release checks passed: zero LuaLS diagnostics, LuaJIT parsing and secondary Lua 5.5 syntax checks for every packaged runtime file.
- ZIP inspected: one mod root containing the manifest, runtime scripts, README and MIT license; no tests, debug tools or workspace metadata.

SHA-256 (`BetterBrainer.zip`):
```text
EB1B3B26A4BE946A6806331CDE4FCEABE69FC42306C42A46312ED20B3CB9D3DF
```
