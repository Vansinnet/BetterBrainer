# BetterBrainer: design
Status 2026-10-28: 1.1.0 released (1.0.5 plus the Drill seed-predicted opening, the Drill fast exit waiting for this session's receipts, and the Balance centre hold). ModID `BetterBrainer`. Verified: static and offline (see Tests); the Drill and Balance code passed in game in NoBrainer; the Frequency pipeline is not yet confirmed in game.
Do not enable together with NoBrainer: both automate the same input.
Relation to NoBrainer (`mods/active/NoBrainer/DESIGN.md`): NoBrainer = this mod + servo skull + Symbols reroll + Search transition skip. Its `frequency.lua`, `scan.lua` and `balance.lua` are identical copies of ours: change them here first, then copy (the Balance centre hold was the exception, built in NoBrainer first and copied here after its in-game checks). Its `drill.lua` is an identical copy again since the seed-predicted opening came here (2026-10-28, built in NoBrainer first). Its `symbols.lua`, `search.lua` and core carry the reroll and transition-skip code, so a fix to those solvers or to the core is made in both mods by hand. Never add reroll or transition skip back to BetterBrainer (user decision 2026-10-25: too strong).

## Files
- `BetterBrainer.lua`: settings cache, input routing (`InputService._get` scoped to the local `HumanInputHandler` samples), session selection from `PlayerCharacterStateMinigame._update_input`, and the server input-state gate.
- `symbols.lua`, `search.lua`, `drill.lua`, `frequency.lua`, `balance.lua`, `scan.lua`: one solver each, `return function(ctx) ... return module end`.
- `BetterBrainer_data.lua`, `BetterBrainer_localization.lua`: options and strings (en, zh-cn, zh-tw, ru).
- `tests/`: offline LuaJIT harnesses on the game's own Lua (`tests/README.md`). `TESTING.md`: validation history and in-game acceptance.

## Decisions
- 2026-10-14 (user: "make it happen", after a read-only speed analysis the same day): build the three largest speed-ups: Search transition skip and Symbols reroll by reopening the terminal, and the Frequency pipeline. Rejected then: seed-predicted Drill and Search openings (they rely on a client reproducing each minigame extension's seed), and the final press and cancel in the same frame (a dropped press frame ends the session unsolved).
- 2026-10-25 (user: "jag vill återgå i betterbrainer till 1.0.4 ... de är för starka"): remove Symbols reroll, Search transition skip and their reopen controller from BetterBrainer; they live on in NoBrainer (its `DESIGN.md` has their design and in-game history). BetterBrainer keeps the Frequency pipeline (user decision the same day). `symbols.lua`, `search.lua`, `BetterBrainer_data.lua` and `BetterBrainer_localization.lua` are the 1.0.4 files; the core is 1.0.4 plus the pipeline's session-frame report, consumed-input flag and neutral first frame. The pipeline acts at speed 5 and needs no setting; it switches itself off for the mission after a mismatch, so failures cost time, never a wrong press.
- 2026-10-28 (user: "Ja, rätta den", after the bug was found in NoBrainer the same day): the Drill fast exit requires this session's receipts (`drill.completed`: `fresh` and `is_completed`). A decoder needs a new hack after every interrupt; `decode_interrupt` returns the solved minigame to gameplay, but the client keeps the solved stage until the new setup's `rpc_minigame_sync_set_stage` (`minigame_drill.lua:57-64`, `minigame_base.lua:52-54,82-92,200-213`, `decoder_device_extension.lua:204-220`). The fast exit then cancelled the new session as soon as the scanner view was open, which the server ran as an ordinary cancel. Shown offline (`tests/reopen_spec.lua`, fails without the fix); how often it happened in game depends on whether the view opens before the receipts, which is unmeasured.

- 2026-10-28 (user: "ja", asked whether the Drill code was in BetterBrainer too): the Drill seed-predicted opening comes here unchanged from NoBrainer, with its client seed counter (`ctx.initial_seed`) and entry-frame minigame lookup in the core. Design, failure handling and the in-game check are in NoBrainer's `DESIGN.md` (Drill seed-predicted opening; Runtime status 2026-10-28). It is not one of the reopen features the 2026-10-25 decision keeps out: it sends the first move earlier and never closes or reopens a terminal.
- 2026-10-28 (user: "bygg den i nobrainer först, och fungerar den bra lägger vi in den i betterbrainer också"; after the in-game checks: "Ja, BetterBrainer"): Balance holds the point as close to the centre as the server allows. NoBrainer's `balance.lua` is copied here unchanged.

## Balance centre hold (`balance.lua`)
- The design, the offline numbers and the in-game checks are in NoBrainer's `DESIGN.md` (Balance centre hold, Runtime status). In short, it cancels the outward push in full and steers along a velocity target toward the centre with a braking curve. The 1.0.4 controller scaled its command by 0.35 and rested about 0.13 radii off centre.
- In game as NoBrainer, client of a mission server, 2026-10-28: the point stayed within 0.01-0.02 radii of the centre between kicks at normal ping, and within 0.03-0.04 at 311 ms. Kick peaks were 0.11-0.14 and 0.28-0.41; it never reached the edge. Not yet run as BetterBrainer in game; the file is byte-identical.

## Frequency pipeline (`frequency.lua`)
- The server scores any test RPC against its current target without checking the sender (`minigame_system.lua:198-218`, `minigame_frequency.lua:252-284`). The next target is drawn from the seed and rerolled against the server's current frequency (`minigame_frequency.lua:67-103`).
- That frequency is set by `generate_board` at every setup and changed only by a non-zero axis in `on_axis_set`. On a dedicated server `update`'s camera path does not run (`minigame_frequency.lua:79-92,138-216`). Setup always sends the stale initial `_start_seed`, so the server's seed lies somewhere on the chain from it.
- At speed 5 the solver never steers, not even before the gameplay receipt. The core makes the first minigame frame's directions neutral: it is sampled before the state initializes the minigame, so no solver owns it yet. A safe hook on `on_axis_set` flags any direction the local player's `_update_input` consumed anyway.
- Prediction:
  - The solver searches the chain from the received start seed (up to 256 draws) for positions whose frequency and redraw rule reproduce the first target.
  - The first target pins where it was drawn, not where setup began: a later start whose frequency skips the same redraws gives the same target. All matching positions must therefore predict the same targets 2 and 3, or the session uses one test per receipt.
  - Offline, 36 of 40 first sessions and 14 of 20 later sessions on the same device pipeline.
- A late first frame would replay the input from before the session (`authoritative_player_input_handler.lua:153-157`). The core records the server's report for the session's first frame (`had_received_input`), and the first armed press waits up to 0.1 s for it. Only an on-time report allows pipelining; a missing or late one means one test per receipt.
- Sending: all three tests go out on that press. Each test answers with exactly one stage receipt, so the solver waits for three, checks every stage and target receipt against the prediction, and switches pipelining off for the mission on any mismatch. Offline, a forced server-side divergence costs at most two mistakes and still solves.
- On a local server it tests each new target in the same frame.

## Source contracts
| Use | Source path:line |
|---|---|
| Entry runs setup before input | `scripts/extension_systems/character_state_machine/character_states/player_character_state_minigame.lua:138-148,183-216,376-402` |
| Cancel and exit | `player_character_state_minigame.lua:206,270-342` (walking on cancel), `:87-125` (on_exit stops the minigame) |
| Frequency scoring and targets | `minigame_frequency.lua:67-115,138-178,252-290`; `scripts/extension_systems/minigame/minigame_system.lua:117-123,198-218` |
| RNG | `math.next_random`, `types/darktide/core.lua` (LCG identified in game, `types/SOURCES.md`) |

## Tests
See `tests/README.md` (command, what it checks, dated result). Offline evidence, not in-game results.
- 2026-10-14, `tests/reopen_spec.lua`: Frequency pipeline mean solve 0.280 -> 0.136 s at 30 ms, 1.120 -> 0.472 s at 165 ms, 0.040 s on a local server; zero mistakes.
- 2026-10-25, after removing reroll and transition skip: `tests/reopen_spec.lua` 6/6 (Frequency cases only, same results), speed 73/73, search 21/21, drill 36/36, scan markers 4/4.
- 2026-10-28, Drill seed-predicted opening: `tests/reopen_spec.lua` 13/13 (the six Frequency cases plus NoBrainer's seven Drill cases, ported with its harness changes); kept board 3.045 s against 3.143 s without the opening at 30 ms receipts, 3.224 s against 3.458 s at 165 ms. Speed 73/73, search 21/21, drill 36/36, balance 7/7, scan markers 4/4.
- 2026-10-28, Drill fast-exit fix: `tests/reopen_spec.lua` 7/7 (6/7 without the fix: the Drill re-hack after a decoder interrupt closed unsolved on every seed it reached), speed 73/73, search 21/21, drill 36/36, scan markers 4/4.

## Runtime status
- 1.0.4: user-tested in remote missions at speed 5 (`TESTING.md`).
- Frequency pipeline (1.0.5): offline only; the remaining steps are in `TESTING.md` under the 2026-10-14 entry.
- Drill fast-exit fix and seed-predicted opening (2026-10-28, unreleased): both passed in game in NoBrainer the same day (identical `drill.lua`, NoBrainer `DESIGN.md`); BetterBrainer's own build is not yet tested in game (`TESTING.md`, 2026-10-28).

## Open items
- 2026-10-14: verify the Frequency pipeline in game as a dedicated-server client at speed 5 (`TESTING.md`, step 3).
