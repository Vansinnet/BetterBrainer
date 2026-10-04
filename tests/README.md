# Focused BetterBrainer speed checks

Run from the workspace root. The first command is the acceptance check for the
speed changes; failures produce exit code 1:

```powershell
& tools\luajit\luajit.exe mods\active\BetterBrainer\tests\speed_spec.lua
```

Pre-edit baseline command:

```powershell
& tools\luajit\luajit.exe mods\active\BetterBrainer\tests\speed_spec.lua --baseline
```

## Fixture and evidence

`fixture.lua` reuses the fixture portion (original lines
1–438) of `tools/tests/better_brainer_spec.lua`, without running its legacy suite.
It pins source loading to `darktide-source/Darktide-Source-Code-1.13.0/`, supplies
LuaJIT `table.pack`/`table.unpack`, preserves the real two-argument `math.atan2`,
and updates the lag-compensation stub to `rewind_seconds` (seconds).

The source classes, HumanInputHandler/InputService/HumanUnitInput,
PlayerCharacterStateMinigame, and MinigameSystem RPC dispatch run from source.
The deterministic RNG, native primitives, DMF hook registration, peripheral
services and queued transport are fixture substitutes. Results establish offline
Lua behavior, not native transport/quantization or dedicated-server operation.

Scan additionally loads the complete `ActionScan`, `ActionScanConfirm`,
`Scanning`, and `MissionObjectiveZoneScannableExtension` source files. The
`scan_settings` literal is extracted from the pinned scanner template. Raycasts
and actor/unit primitives are mocked; shared weapon-base start/finish side
effects are stubbed. The harness drives the action transitions explicitly rather
than loading the weapon action manager. Native Lua acquisition, confirm finish,
banking, component clearing, and scannable activity checks remain source code.

Relevant contracts in the pinned source:

| Source path under `scripts/` | Evidence used |
| --- | --- |
| `extension_systems/minigame/minigames/minigame_decode_symbols.lua` | `setup_game` sends symbols, all targets, stage 1; `start` uses `rewind_seconds`; native hit-window oracle and concrete setters |
| `extension_systems/minigame/minigame_system.lua:133–172` | Cursor/stage/board/target receivers; clock converts fixed-frame ID into seconds |
| `extension_systems/minigame/minigames/minigame_decode_search.lua:203–257` | Diagonal movement sends X-only then full cursor RPCs |
| `extension_systems/minigame/minigames/minigame_frequency.lua:252–290` | Native scoring and stage-one failure sends unchanged stage without a target replacement |
| `extension_systems/character_state_machine/character_states/player_character_state_minigame.lua` | Native local initialization, serialized input consumption, and exit |
| `extension_systems/weapon/actions/action_scan.lua:21–66` | Scan start/acquisition |
| `extension_systems/weapon/actions/action_scan_confirm.lua:56–70,114–168` | Abort/finish, bank, validity, and component clearing |
| `utilities/scanning.lua:40–66,111–139` | Raycast result layout and `(unit, line_of_sight)` returns |
| `settings/equipment/weapon_templates/devices/scanner_equip.lua:152–175,267–299` | Confirm time 1s and return-to-scan action chain |

No runtime solver is copied or replaced. Runtime module strings are read once
per process so all cases use one consistent snapshot. No files are written by
the tests. The adapter's only fixture-text substitutions correct `atan2` and
`rewind_seconds`; source-path routing and vararg helpers are adapter-local.

## Coverage

`speed_spec.lua` runs 73 focused cases:

- **Frequency:** speeds 1/3/5 opening timing; missing initial stage/target;
  stage-first and target-first ACKs, including repeated numeric targets;
  unchanged-stage failure ACK; native successful scoring and release edges.
- **Search:** first fully acknowledged sample; partial diagonal and same
  movement-frame suppression; slower-speed settling and movement `ready_at`;
  native cursor movement/scoring and mandatory release.
- **Symbols:** seven receipt orders, each with local start before/midway/after;
  each missing target, stage, or clock; duplicate targets; completion after an
  already-observed partial board; clock/targets preceding `set_symbols`; early
  receipt invalidation by real stop or foreign start; same-instance exit/reopen,
  including fresh receipts with the same numeric clock; continuing argumentless
  start/stop; ambiguous-session 120ms fallback; leading and trailing 30ms hit
  margins on both sweep directions, checked against native `is_on_target`.
- **Scan:** both update-side and input-side abort paths; same-target cooldown;
  different eligible target waits for `action_scan` then starts immediately;
  no duplicate press; native bank's target-specific ACK guard.
- Six complete Frequency/Search/Symbols solves at speed 5 where available, seed
  1729, with 30/165 ms receipt delays and 60 ms delayed server input; all finish
  with zero server mistakes. These independently scripted delays are not a
  native RTT model. An additional early-stop/new-clock check ensures a clock
  alone cannot revive retired fast-path board proof.

The receipt-order cases deliberately reorder source-generated setup RPCs. This
tests the Lua gate's order independence, not the ordering of native transport.
Retained target arrays are already populated, so missing-receipt tests cannot
pass merely because an old target happens to be nil. Local and simulated remote
states consume the source input buffer; scoring assertions require an actual
engine-source state transition, not a test reimplementation of a solver.

## Baseline and last results

Baseline was run **before any runtime edit**, against BetterBrainer commit
`b5733668a9f5ea0fae0f05a3118c76e05888635e` (runtime working tree clean), using
Windows LuaJIT `2.1.1703358377`, source **1.13.0**, on **2026-10-03**.

`--baseline` changes only the expected timing/edge assertions. It does **not**
reverse-transform runtime code or load a saved old solver. It is a pre-edit
measurement mode, not a command expected to pass after the speed edits land.
Use the default command for the final acceptance run.

| Check | Measured pre-edit first edge | Measured post-edit first edge |
| --- | ---: | ---: |
| Frequency speed 1, 10ms test sampling | 0.750s | 0.750s |
| Frequency speed 3, 10ms test sampling | 0.630s | 0.380s |
| Frequency speed 5, 10ms test sampling | 0.500s | 0.020s |
| Search after full cursor ACK, 20ms sampling | +0.020s | same sample |
| Symbols complete receipts, release sample at t=0 | 0.121s probe | 0.010s probe |
| Scan different target after abort, scan resumes at +0.020s | 0.301s probe | 0.020s probe |

These are scripted observation times, not wall-clock benchmarks. Boundary
probes intentionally bracket 120ms/300ms delays. Frequency speed 5's required
zero opening timer still preserves the first-sample release. Symbols also
preserves that release and the safe native hit window.

Last runs:

- Before edits, `speed_spec.lua --baseline`: **66 passed, 0 failed**, exit 0.
- Before edits, post-edit expectations: **31 passed, 35 failed**, exit 1. Failures
  were 2 Frequency faster-opening cases, 1 Search immediate-ACK case, 30 Symbols
  receipt-fast-path cases, and 2 Scan different-target cases.
- After edits and seven additional regressions, `speed_spec.lua`: **73 passed,
  0 failed**, exit 0, on 2026-10-03.

Both harness files load and execute in LuaJIT. Canonical changed-runtime
validation is recorded in `../TESTING.md`; normal runtime validation excludes
this tests directory. No live game access occurred.

## Drill checks (`drill_spec.lua`)

```powershell
& tools\luajit\luajit.exe mods\active\BetterBrainer\tests\drill_spec.lua
& tools\luajit\luajit.exe mods\active\BetterBrainer\tests\drill_spec.lua --baseline
```

The default run is the acceptance check for the Drill aim planner and transition hold. `--baseline` relaxes the new-behaviour assertions so the same file can run against an older `drill.lua` for comparison; it expects the old origin-node stall.

Boards come from the real `MinigameDrill:generate_targets` with the fixture RNG and chosen seeds (`MinigameDrill.init` is wrapped only to change the seed). Ground truth for "one direction can reach the node" comes from calling the native `on_axis_set` on a scratch server instance over 0.1-degree steps. Every move the server accepts is recorded, including moves that select nothing. The tests simulate a late server resume by moving the server's `_transition_start_time`, replay the last received input frame on the server (as `authoritative_player_input_handler.lua:153-156` does for late input), delay chosen RPCs in the queued transport (optionally in order), quantize `Network.pack_unpack` to 1/127, start without `Network.type_index` to force direct aim, change the native distance weight after load, and rotate the server's aim to model a joystick error the planner cannot see.

Input stalls replay the last frame the server consumed for 12 or 20 frames from a chosen frame after the first stage-2 gameplay frame; the check requires zero mistakes and a solve (no exit). A further check drops all server state.

Last results (2026-10-04, Linux LuaJIT 2.1.1788856981, source 1.13.0): **36 passed, 0 failed**, about 130 seconds. With `--baseline` against the 1.0.2 `drill.lua`: the earlier checks pass with baseline expectations (it reports 9 of 37 stalls under replayed input); the version before the server-state gate and retry exits on 20 and 16 of 80 stalled boards. Timing comparisons are in `../TESTING.md`. These are offline fixture results, not live measurements.

## Search pre-send checks (`search_spec.lua`)

```powershell
& tools\luajit\luajit.exe mods\active\BetterBrainer\tests\search_spec.lua
& tools\luajit\luajit.exe mods\active\BetterBrainer\tests\search_spec.lua --baseline
```

Boards come from the real `MinigameDecodeSearch:generate_board` with the fixture RNG (`init` is wrapped only to change the seed). The tests record stage-advancing presses and cursor moves on the native server, delay the server's resume by moving `_state_start_time`, replay the last received input frame on the server, delay cursor receipts (optionally in order), drop one press, reopen the same terminal mid-stage with the cursor off-centre (plain, after a settings change, and on the target with receipts stalled 1 s), stall input for 12 or 20 frames from each of the first six frames after a stage-2 step at 50/165/300 ms receipts, drop all server state, and run on a local server and at speed 3.

Last results (2026-10-04): **21 passed, 0 failed**, about 70 seconds. With `--baseline`, the stall check at 300 ms reports a mistake on 6 of 120 boards for the 1.0.2 `search.lua` and 20 of 120 for the pre-send without the gate; that version also fails the settings and stalled-receipt reopen checks. `fixture.lua` gives each fixture a no-op `mod:debug` that tests may replace to capture DMF debug lines.

## Server input state in the fixture

`fixture.lua` models the server's per-tick `server_unit_data_state` (`player_unit_data_extension.lua:984-991`): the fixture's server runs client frame n in tick n + 3, and reports frame n with `had_received_input = true` unless a test substituted older input for it. The state is queued to the client behind the RPCs of that frame with the normal receipt delay and read through the mod's real hook on a stub `PlayerUnitDataExtension._read_server_unit_data_state` (`f:report_frame(frame, had)` delivers one by hand; `speed_spec.lua` uses it where it drives single frames; `f.drop_server_state = true` drops every state). The real server reports once per tick, usually a frame or more after the input arrived, so the fixture's wait is close to the real one. The fixture cannot reorder state ahead of RPCs; that remaining assumption is described in `../TESTING.md`.
