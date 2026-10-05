# BetterBrainer

Current release: **1.0.3**.

A standalone DMF mod for Darktide minigame assistance. This is a new implementation, not a dependency or extension of NoBrainer.

## Features

- Decode Symbols: timed automatic presses with up to two predicted stages awaiting receipt, and up to three upcoming solution highlights.
- Decode Search: matching-region highlights, up to two predicted cursor moves including diagonals at low ping, and one outstanding move at RTT >= 250 ms. Submission waits for the cursor to settle with no pending moves. Receipt timeout follows ping with a 0.8-second floor. Unexpected or timed-out movement triggers neutral resynchronization with backoff capped at 3.2 seconds; full cursor confirmation clears fault caution but never bypasses the high-ping cap.
- Drill: correct-node highlights, navigation, and submission after native searching completes. Each move is planned with the game's own node-selection rule on the joystick values the server receives, so one move reaches the correct node whenever any single direction can. Search and Drill use normal cancel input after observed completion to skip the final outro.
- Frequency: directional arrows and proportional steering, plus direct submission of the known target on an automated consumed press. Submission does not wait for the displayed waveform to align.
- Balance: bounded, latency-aware predictive steering.
- Auspex Scan: scannable-object highlights and automatic confirmation while aiming at an eligible target. A highlight stays on until the server has banked that object's scan and goes out as soon as it has.

At speed 5, Frequency starts as soon as its opening receipts and initial release permit, and Search submits on the first fully confirmed target sample after movement. Symbols skips its 120 ms stability wait when a complete fresh board has been received. After an interrupted scan, a different target can begin immediately once the scanner returns to scan mode; the same target retains its retry delay. At speed 5, Drill holds the next stage's first move from the end of the 0.6-second stage transition until its result arrives, so the server takes it on its first gameplay frame. It holds only a direction that selects the correct node from the start and selects nothing from that node, so repeats and replayed input cannot move off it (about 89% of transitions offline). If the stage receipt arrives after the expected resume (very high ping), it holds at once but only for two to five frames. At speed 5 against a remote server, Search sends the next stage's first step (and, within the normal two-move window, the second) on the expected resume frame: the first step is held for 0.08 seconds from press + 0.25 seconds, well inside the 0.25-second repeat delay. Search waits for both steps to be confirmed before queuing more, and a missed or unexpected result goes through the existing timeout and resynchronization and switches the pre-send off until the next mission. A local server skips it. Opening Search while the client still shows an earlier session's cursor (ours or another player's) waits for the server's recentre before Search moves or presses.

Lag safety: while input frames arrive late, the server keeps running an older input frame, so a direction caught by a lag spike repeats after the 0.25-second repeat delay and can move past a position the client has already seen confirmed. Against a remote server, Search and Drill therefore submit only after the server's state for this player shows that it ran a later frame on its own, timely input; earlier input can never run after that, so lag costs time (resynchronization) but not a wrong press. A repeated press, after 1.2 s without a stage receipt, needs the same proof for the earlier press. A Drill move with no result for 2.5 seconds is retried with direct aim once the server has run later input (the move was lost); without server state Drill still leaves the minigame, as before. This relies on a minigame RPC arriving before server state sent after it. Native Drill searching/transitions, Balance objective duration and one-second scan confirmation still apply.

Drill acknowledges a move only through its own selection (the server's search start lies within 0.125 s of the move's input frame), so a late result of an earlier move never releases a submission. After a held move's result arrives more than 0.7 seconds late, the submission waits one more receipt delay in case a repeat's result is still in flight. A selection the server did not confirm as predicted, or one no Drill move explains, switches aim prediction and holding off until the next mission; Drill then aims directly. A hold without a result within 2.5 seconds (the tolerance every move is given) switches only holding off.

There are 15 controls across six feature groups plus language selection. All checkboxes default on; the three solver speeds default to 1 (range 1-5), and language defaults to automatic. English, Simplified Chinese, Traditional Chinese and Russian can be selected explicitly; language changes require restart. Settings belong to the new mod ID; NoBrainer settings are not migrated.

## Installation Identity

The installed directory, manifest and DMF ID are all `BetterBrainer`. Add `BetterBrainer` to the installed `mod_load_order.txt` after deployment through your normal DMF workflow.

**Do not enable NoBrainer and BetterBrainer together.** Both automate the same game input. BetterBrainer does not modify or disable other mods.

## Downloads

Download `BetterBrainer.zip` from the [latest release](../../releases/latest). It contains the installed `BetterBrainer` folder, its `.mod` manifest, required `scripts/` files, README and license. Do not use GitHub's automatically generated source-code archives for installation.

## Implementation

The core routes only input actually collected by the local player's `HumanInputHandler`. Fixed-frame movement and held buttons share a decision; unrelated service/UI reads do not consume commands. Native character-state input, animations, input locks, and network serialization remain in place.

Symbols, Search, Drill, Frequency and Balance share a missing-owner fallback only on clients: the exact local Player's live unit, state unit, selected minigame and actual current CSM state must agree. Explicit foreign owners and nil-owner local authority are rejected. Normal explicit-owner input keeps its existing fast path; Frequency also checks actual state identity at consumed-press, scoring and final RPC boundaries. No owner is assigned, minigame restarted or native input lock bypassed.

Harmless Symbols start-without-player receipts preserve the board clock, synchronization gates and pending predictions. A stop-without-argument receipt while that exact local client state continues rearms only the pulse, because native stop clears its held-edge state. Pending deadlines remain intact. Real stop(Player), board replacement and exit keep their existing cleanup.

Symbols records start-clock receipts against the exact minigame and cloned board, including receipts arriving before local unit initialization. Local start consumes that evidence instead of misclassifying the fresh clock as a stopped clock. Foreign starts and real stops retire it; a retained board without a fresh eligible receipt remains blocked. A new receipt can reuse the same numeric fixed-frame clock. A new symbols table followed by every target receipt, stage 1 and its matching clock permits immediate readiness; ambiguous already-open sessions retain the 120 ms stability fallback. The engine clock, initial release and 30 ms hit-window margin still apply.

Search reuses its once-per-second RTT poll. A high sample caps future movement without discarding already-pending commands; a below-250-ms sample restores two only when the pending queue is empty. Missing/invalid ping keeps the existing zero-RTT fallback and 0.8-second timeout floor, with the same empty-queue expansion rule. Local authority keeps two. The 250-ms threshold is a conservative policy, not an engine limit or measured failure boundary. High ping trades throughput for one move per full acknowledgement rather than extrapolating another move from an unconfirmed position. This mitigation does not establish or fix the reported wrong-way cursor root cause; native replay of late movement input remains possible.

Symbols, Search, Drill and Frequency share `ctx.pulse`: the first sampled fixed frame releases, a ready press occupies one sampled frame, and the next sampled frame releases. Primary aliases agree within each frame. This replaces the old timed press/cadence model; solver-specific pacing and receipt checks still apply. Symbols retains pending submissions until stage receipts arrive, and disables prediction ahead on unexpected stage/mistake changes or timeout rather than treating a timeout as success.

Frequency is an explicit payload exception: for its own active, armed press consumed by native `MinigameBase.action`, it suppresses the native current-frequency submission and sends the known target through the existing Frequency test RPC. It waits for both stage and target receipts before another client submission, except a failed stage-one attempt needs only the stage-one receipt because the engine retains that target. Local-server scoring uses the same target and guards against duplicate scoring by SoloPlay's safe hook. Other presses retain native handling, and the action wrapper preserves all chained return values. No new RPC protocol or generic server-completion call is added; Search/Drill fast exit uses the normal ephemeral cancel and native teardown only after `is_completed()` is observed.

Uncertain Symbols/Frequency submissions use a separate failure-abort path, not fast success. When Symbols' oldest pending press reaches 2.5 seconds in gameplay time, or Frequency's required receipts remain incomplete for 2.5 seconds, the core requests one ordinary cancel under the existing input locks, ownership and scanner-view gates. Frequency latches that abort even if late receipts arrive. Pending work is not blindly discarded to retry the uncertain submission. The terminal does not automatically reopen after this abort; manually reopen it to start a fresh session. A real Symbols client start rejects the raw retained clock unless eligible early receipt evidence identifies it as fresh.

Solvers own their state. Rendering does not execute solver actions. Settings and derived speed factors are cached; widgets and bounded prediction buffers are reused. Only scan needs background updates. No custom assets or packages are loaded.

## Verification

The current speed revision passes **73/73 focused offline LuaJIT tests**, loading Darktide 1.13.0 Lua input, character-state, scoring and RPC implementations with mocked native services and transport. Run from the workspace root:

```powershell
& "tools\luajit\luajit.exe" "mods/active/BetterBrainer/tests/speed_spec.lua"
& "tools\luajit\luajit.exe" "mods/active/BetterBrainer/tests/drill_spec.lua"
& "tools\luajit\luajit.exe" "mods/active/BetterBrainer/tests/search_spec.lua"
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\validate.ps1" -Path "mods\active\BetterBrainer"
```

Coverage includes receipt ordering, stale-board rejection, target-specific scan retry, input release edges and complete zero-mistake solves under simulated receipt delays. The Drill suite (36 checks) compares every move with the native selection, and covers late server resumes, replayed late input, delayed or late receipts, high ping, origin nodes, deliberately wrong selection and joystick models with latency spikes, input stalls with lost moves, and local-server play. The Search suite (21 checks) covers the pre-send timing, late resumes, replayed late input, input stalls at up to 300 ms receipts, late receipts, a dropped press, reopening mid-solve (also after a settings change and with stalled receipts), missing server state, local-server play and speed 3. Both suites model the server's per-frame input state. Drill and Search write diagnostic lines through DMF debug logging, which is off by default (DMF options: Logging mode Custom, Debug output Log). The historical 173-test suite describes an earlier revision. See `tests/README.md` for timing comparisons and fixture limits, and `TESTING.md` for static validation and remaining in-game acceptance.

User-reported remote-mission tests at speed 5 confirmed Drill's planned holds and Search's pre-send and recentre fix. The latest server-input-state gate and Drill lost-move retry still need in-game confirmation; exact game build, mission, RTT and complete lifecycle coverage were not recorded. Release validation checks every packaged Lua/manifest file; the offline harness requires the development workspace and its engine sources. Detailed `TESTING.md` remains local development documentation.

## Credits

Feature behavior and existing translations are based on NoBrainer. Traditional Chinese translation attribution is retained in the localization file.

## License

Licensed under the [MIT License](LICENSE).
