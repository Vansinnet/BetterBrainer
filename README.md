# BetterBrainer

A standalone DMF mod for Darktide minigame assistance. This is a new implementation, not a dependency or extension of NoBrainer.

## Features

- Decode Symbols: timed automatic presses with up to two predicted stages awaiting receipt, and up to three upcoming solution highlights.
- Decode Search: matching-region highlights, up to two predicted cursor moves including diagonals at low ping, and one outstanding move at RTT >= 250 ms. Submission waits for the cursor to settle with no pending moves. Receipt timeout follows ping with a 0.8-second floor. Unexpected or timed-out movement triggers neutral resynchronization with backoff capped at 3.2 seconds; full cursor confirmation clears fault caution but never bypasses the high-ping cap.
- Drill: correct-node highlights, navigation, and submission after native searching completes. Search and Drill use normal cancel input after observed completion to skip the final outro.
- Frequency: directional arrows and proportional steering, plus direct submission of the known target on an automated consumed press. Submission does not wait for the displayed waveform to align.
- Balance: bounded, latency-aware predictive steering.
- Auspex Scan: scannable-object highlights and automatic confirmation while aiming at an eligible target.

There are 15 controls across six feature groups plus language selection. All checkboxes default on; the three solver speeds default to 1 (range 1-5), and language defaults to automatic. English, Simplified Chinese, Traditional Chinese and Russian can be selected explicitly; language changes require restart. Settings belong to the new mod ID; NoBrainer settings are not migrated.

## Installation Identity

The installed directory, manifest and DMF ID are all `BetterBrainer`. Add `BetterBrainer` to the installed `mod_load_order.txt` after deployment through your normal DMF workflow.

**Do not enable NoBrainer and BetterBrainer together.** Both automate the same game input. BetterBrainer does not modify or disable other mods.

## Downloads

Download `BetterBrainer.zip` from the [latest release](../../releases/latest). It contains only the installed `BetterBrainer` folder, its `.mod` manifest, and required `scripts/` files. Do not use GitHub's automatically generated source-code archives for installation.

## Implementation

The core routes only input actually collected by the local player's `HumanInputHandler`. Fixed-frame movement and held buttons share a decision; unrelated service/UI reads do not consume commands. Native character-state input, animations, input locks, and network serialization remain in place.

Symbols, Search, Drill, Frequency and Balance share a missing-owner fallback only on clients: the exact local Player's live unit, state unit, selected minigame and actual current CSM state must agree. Explicit foreign owners and nil-owner local authority are rejected. Normal explicit-owner input keeps its existing fast path; Frequency also checks actual state identity at consumed-press, scoring and final RPC boundaries. No owner is assigned, minigame restarted or native input lock bypassed.

Harmless Symbols start-without-player receipts preserve the board clock, synchronization gates and pending predictions. A stop-without-argument receipt while that exact local client state continues rearms only the pulse, because native stop clears its held-edge state. Pending deadlines remain intact. Real stop(Player), board replacement and exit keep their existing cleanup.

Symbols records start-clock receipts against the exact minigame and cloned board, including receipts arriving before local unit initialization. Local start consumes that evidence instead of misclassifying the fresh clock as a stopped clock. Foreign starts and real stops retire it; a retained board without a fresh eligible receipt remains blocked. A new receipt can reuse the same numeric fixed-frame clock. The engine clock and cursor calculation are unchanged, including clocks numerically ahead of gameplay time, and the existing stable-board wait remains in place.

Search reuses its once-per-second RTT poll. A high sample caps future movement without discarding already-pending commands; a below-250-ms sample restores two only when the pending queue is empty. Missing/invalid ping keeps the existing zero-RTT fallback and 0.8-second timeout floor, with the same empty-queue expansion rule. Local authority keeps two. The 250-ms threshold is a conservative policy, not an engine limit or measured failure boundary. High ping trades throughput for one move per full acknowledgement rather than extrapolating another move from an unconfirmed position. This mitigation does not establish or fix the reported wrong-way cursor root cause; native replay of late movement input remains possible.

Symbols, Search, Drill and Frequency share `ctx.pulse`: the first sampled fixed frame releases, a ready press occupies one sampled frame, and the next sampled frame releases. Primary aliases agree within each frame. This replaces the old timed press/cadence model; solver-specific pacing and receipt checks still apply. Symbols retains pending submissions until stage receipts arrive, and disables prediction ahead on unexpected stage/mistake changes or timeout rather than treating a timeout as success.

Frequency is an explicit payload exception: for its own active, armed press consumed by native `MinigameBase.action`, it suppresses the native current-frequency submission and sends the known target through the existing Frequency test RPC. It waits for both stage and target receipts before another client submission, except a failed stage-one attempt needs only the stage-one receipt because the engine retains that target. Local-server scoring uses the same target and guards against duplicate scoring by SoloPlay's safe hook. Other presses retain native handling, and the action wrapper preserves all chained return values. No new RPC protocol or generic server-completion call is added; Search/Drill fast exit uses the normal ephemeral cancel and native teardown only after `is_completed()` is observed.

Uncertain Symbols/Frequency submissions use a separate failure-abort path, not fast success. When Symbols' oldest pending press reaches 2.5 seconds in gameplay time, or Frequency's required receipts remain incomplete for 2.5 seconds, the core requests one ordinary cancel under the existing input locks, ownership and scanner-view gates. Frequency latches that abort even if late receipts arrive. Pending work is not blindly discarded to retry the uncertain submission. The terminal does not automatically reopen after this abort; manually reopen it to start a fresh session. A real Symbols client start rejects the raw retained clock unless eligible early receipt evidence identifies it as fresh.

Solvers own their state. Rendering does not execute solver actions. Settings and derived speed factors are cached; widgets and bounded prediction buffers are reused. Only scan needs background updates. No custom assets or packages are loaded.

## Verification

The offline integration suite passed **173/173 tests**. It uses the actual engine `class.lua` with copied inheritance, engine Lua input/character-state/scoring and RPC implementations, and mocked native services and transport. Run from the workspace root:

```powershell
& "lua-5.5.0_Win64_bin\lua55.exe" "tools/tests/better_brainer_spec.lua"
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\validate.ps1" -Path "mods\active\BetterBrainer"
```

The suite now verifies that the retired setting and module path are absent while preserving the Symbols solve, receipt, ownership, lifecycle and failure-cancel coverage. Canonical validation passes with zero LuaLS diagnostics and syntax checks for all runtime and manifest files; the test file also passes syntax validation. No deployment, live connection or mutation was performed. See `TESTING.md` for the exact historical runtime context and remaining acceptance.

## Credits

Feature behavior and existing translations are based on NoBrainer. Traditional Chinese translation attribution is retained in the localization file.

## License

Licensed under the [MIT License](LICENSE).
