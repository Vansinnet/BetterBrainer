# BetterBrainer 1.0.4

## Fix

- Auspex Scan highlights now clear as soon as the server confirms that an object has been scanned, instead of waiting for the next one-second refresh.
- Objects stay highlighted while aiming away, during interrupted scans and through the client's predicted confirmation. The game's own requested outlines are preserved when BetterBrainer releases its marker.

## Validation

- 77/77 offline LuaJIT checks pass against Darktide 1.13.0 Lua source: four Scan marker checks and 73 speed/regression checks.
- All nine runtime Lua files pass LuaLS with zero diagnostics; all nine Lua files and the manifest pass LuaJIT loading and secondary Lua 5.5 syntax checks.
- The ZIP's 12 files pass CRC checks and match the authoritative source and SHA-256 manifest.
- This Scan change has not yet been tested in game. Dedicated-server highlight timing, host/solo operation and lifecycle cleanup remain pending. The earlier server-input-state gate and Drill lost-move retry also retain their documented runtime limitations.

## Installation

Download **BetterBrainer.zip** below and extract the `BetterBrainer/` folder into your DMF mods directory. Add `BetterBrainer` to `mod_load_order.txt`. Do not enable BetterBrainer and NoBrainer together.

Use the installation ZIP rather than GitHub's automatically generated source archives.

ZIP SHA-256: `63d2a81ff2b12a570d87e76bf6dfd6dec02fd9bf18e54ae36352f72eb814dca4`.
