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
