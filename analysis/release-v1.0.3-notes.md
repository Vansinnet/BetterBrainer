# BetterBrainer 1.0.3

## Improvements

- Drill plans movement using the game's node-selection rule and the joystick values received by the server, reducing unnecessary extra moves.
- At speed 5, Drill and Search send the next stage's first movement during the transition, reducing receipt-delay overhead.
- Search and Drill wait for the server to have processed later, timely input before submitting, preventing stale movement from causing a wrong press during input stalls.
- Drill retries a lost move with direct aim once server state proves that the old input cannot run again.
- Search waits for the server to recentre the cursor when reopening a terminal, including after a settings change.
- Fixed Drill getting stuck on a target at the cursor's starting position.
- Prediction fallbacks reset at the next mission. Optional DMF debug logging records movement and acknowledgement decisions.

Settings, defaults and translations are unchanged.

## Validation

- 130/130 offline LuaJIT checks pass against Darktide 1.13.0 Lua source: 73 speed, 36 Drill and 21 Search checks.
- All nine runtime Lua files pass LuaLS with zero diagnostics; all nine Lua files and the manifest pass LuaJIT loading and secondary Lua 5.5 syntax checks.
- User-reported remote-mission tests at speed 5 confirmed Drill holds, Search pre-send and the terminal-reopen fix. The latest server-input-state gate and Drill lost-move retry remain unconfirmed in game. Lifecycle and local-server acceptance are not complete.
- Offline transport is mocked. Ordering of native minigame RPCs relative to later server-state updates remains an assumption; sustained extreme input lateness can leave Search waiting for timely input.

## Installation

Download **BetterBrainer.zip** below and extract the `BetterBrainer/` folder into your DMF mods directory. Add `BetterBrainer` to `mod_load_order.txt`. Do not enable BetterBrainer and NoBrainer together.

Use the installation ZIP, rather than GitHub's automatically generated source archives.
