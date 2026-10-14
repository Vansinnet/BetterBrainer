# BetterBrainer: design
Status 2026-10-14: 1.0.4 released; 1.1.0 in development (reopen-based speed-ups). ModID `BetterBrainer`. Verified: static and offline (see Tests); the 1.1.0 changes are not yet confirmed in game.
Do not enable together with NoBrainer: both automate the same input.

## Files
- `BetterBrainer.lua`: settings cache, input routing (`InputService._get` scoped to the local `HumanInputHandler` samples), session selection from `PlayerCharacterStateMinigame._update_input`, server input-state gate, and the reopen controller.
- `symbols.lua`, `search.lua`, `drill.lua`, `frequency.lua`, `balance.lua`, `scan.lua`: one solver each, `return function(ctx) ... return module end`.
- `BetterBrainer_data.lua`, `BetterBrainer_localization.lua`: options and strings (en, zh-cn, zh-tw, ru).
- `tests/`: offline LuaJIT harnesses on the game's own Lua (`tests/README.md`). `TESTING.md`: validation history and in-game acceptance.

## Decisions
- 2026-10-14 (user: "make it happen", after a read-only speed analysis the same day): build the three largest speed-ups. Search skips its stage transitions by reopening the terminal, Symbols rerolls slow boards by reopening, and Frequency sends all three tests at once from predicted targets. Rejected for now:
  - Seed-predicted openings (Drill, Search, exact Symbols lookahead): they rely on the client reproducing each minigame extension's seed (`level_seed` plus registration order, `minigame_system.lua:61-71`), which is unverified on a dedicated-server client.
  - Final press and cancel in the same frame: a dropped press frame with a timely cancel ends the session unsolved, and Drill and Symbols then lose all progress. It would gain only about one ping of player control.
- New settings: `decode_reroll_limit` (0-8, default 0 = off; user decision 2026-10-14) and `enable_expedition_reopen` (default off, user decision 2026-10-14; it acts at speed 5 only, like the existing pre-send). The Frequency pipeline acts at speed 5 and needs no setting.
- Every reopen feature has a kill switch for the rest of the mission after any failure, like the Search pre-send and Drill holding. Failures cost time, never a wrong press.

## Reopen controller (`BetterBrainer.lua`)
- Why: a decoder terminal's `decoding` interaction takes 0 s (`interaction_templates.lua:36-43`) and is allowed again 0.1 s after the last success while the minigame is inactive (`decoder_device_extension.lua:292-305`). Every entry runs `setup_game` on the server before that frame's input (`player_character_state_minigame.lua:138-148,376-402`).
  - Search keeps its board and stage, recentres the cursor and is in gameplay at once (`minigame_decode_search.lua:68-86`; `minigame_base.lua:34-36,82-92`). Reopening therefore replaces the 0.25 s transition (`minigame_decode_search.lua:163-165`) with a few frames.
  - Symbols builds a new board on every setup (`minigame_decode_symbols.lua:93-144`).
  - Drill cannot use this, because its setup resets the stage to 1 (`minigame_drill.lua:71-94`).
- How: a solver calls `ctx.reopen_ready(mg, t)`, then `ctx.request_reopen(mg)`. The controller then:
  1. Injects the ordinary ephemeral cancel (`action_two_pressed`, `player_character_state_minigame.lua:206,307-309`).
  2. On the local `on_exit`, suspends the solver instead of resetting it.
  3. Injects `interact_pressed` (`base_interaction.lua:57-59`) once the interactor would pick the terminal (`InteractorExtension._find_interaction_object`, `interactor_extension.lua:567-588`), `can_interact(terminal, "decoding")` holds, and 0.15 s have passed since the session started. That is 0.05 s of margin over the native gate.
  4. When the new session of the same minigame starts, resumes the solver (`module.resume`).
  While the reopen is in flight every routed action is neutral, so a held fire or jump key cannot act in the walking state.
- Precondition at request: the terminal is a `decoding` interactee with a decoder device, and the interactor already finds it as chosen or focus target. During the minigame it is only a focus target, because `interaction_allowed` is false while the minigame is active.
- Timing: the client's interactor runs before the character state machine in a fixed frame (`extension_system_configuration.lua:361,397`), and the interaction completes in the frame it starts (`interactor_extension.lua:325-397`). The sequence is: cancel frame, interact frame (the CSM enters minigame in the same frame), setup frame (that frame's input already counts). The server runs the same frames in order, so the client does not wait for any receipt.
- Failure: no new session within 1 s of the request, or a session that ends within 1 s of a resume (rollback after a server rejection), switches reopening off until the next mission. A solver still in its old session gets `reopen_failed()`; a suspended one is reset.
- Side effects: the owner also receives the server's `rpc_minigame_sync_stop` for the old session after the new local start (`minigame_base.lua:172-181`). Client stop clears `_player_session_id` and `_action_held` only. The missing-owner path of `ctx.session_valid` already covers that, and every solver releases before pressing again. Teammates see the auspex close and reopen.

## Search transition skip (`search.lua`)
- At speed 5, with `enable_expedition_reopen`, a stage-advancing press below the last stage requests a reopen. Its cursor was confirmed as usual.
- On resume the solver plans the next stage from the centre at once. Until the stage receipt it uses the predicted stage, and it treats the displayed transition state as gameplay. The displayed cursor is ignored until the recentre receipt (`recentred[mg]`, set by the existing `set_cursor_position` hook), with the usual ack timeout.
- Presses still need the receipt stage, a confirmed cursor and the server input-state proof, so a prediction can never cause a wrong press.
- If the press is proven lost (the server ran later timely input and the stage did not advance), it plans the old stage again.
- Recentring also shortens the next path: 4.09 instead of 5.43 steps per board, and no 3-4 step paths (scratch simulation 2026-10-14).

## Symbols reroll (`symbols.lua`)
- At the first moment a fresh board can be pressed (stage 1, complete receipts), the solver computes its own time to the last press. The model is the press rule of `input()`: hit window less 30 ms, frame grid, two frames between presses, a third press waits for the first receipt.
- It rerolls while that time exceeds the reopen delay plus the optimal value of a fresh board with one reroll fewer, plus 0.15 s. The fresh-board value is a finite-horizon optimal stopping value over all 1512 equally likely target sequences, at the measured decision phase and receipt delay.
- The reopen delay starts at ping + 0.15 s and is then measured. The cap is `decode_reroll_limit` per hack.
- The scratch model with ping 0.06-0.2 s gives a mean board of 5.1 s, 4.0-4.2 s at cap 4 (1.5 rerolls on average) and 3.8-4.0 s at cap 8.

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
| Re-entry | `scripts/extension_systems/character_state_machine/character_states/player_character_state_walking.lua:150-156`; `scripts/extension_systems/interaction/interactions/decoding_interaction.lua:11-34` |
| Interaction gate | `scripts/extension_systems/decoder_device/decoder_device_extension.lua:292-305`; `scripts/settings/interaction/interaction_templates.lua:36-43` |
| Interactor | `scripts/extension_systems/interaction/interactor_extension.lua:160-244,290-405,567-588,753-787`; `interactee_extension.lua:137-176`; `scripts/utilities/attack/player_unit_status.lua:40-44,276-285` |
| Search setup keeps stage | `scripts/extension_systems/minigame/minigames/minigame_decode_search.lua:68-86,150-166,203-257` |
| Symbols setup builds a board | `minigame_decode_symbols.lua:93-144,183-211` |
| Frequency scoring and targets | `minigame_frequency.lua:67-115,138-178,252-290`; `scripts/extension_systems/minigame/minigame_system.lua:117-123,198-218` |
| RNG | `math.next_random`, `types/darktide/core.lua` (LCG identified in game, `types/SOURCES.md`) |

## Tests
See `tests/README.md` (command, what it checks, dated result). Offline evidence, not in-game results.
- 2026-10-14, `tests/reopen_spec.lua` 17/17. Mean solve times without and with the change:

  | Case | Receipt delay | Before | After |
  |---|---|---|---|
  | Search (transition skip) | 30 ms | 1.271 s | 0.757 s |
  | Search | 165 ms | 2.000 s | 1.264 s |
  | Search | local server | 0.710 s | 0.418 s |
  | Symbols (reroll limit 4) | 30 ms | 5.497 s | 4.091 s |
  | Symbols | 165 ms | 5.637 s | 4.845 s |
  | Symbols | local server | 5.449 s | 4.003 s |
  | Frequency (pipeline) | 30 ms | 0.280 s | 0.136 s |
  | Frequency | 165 ms | 1.120 s | 0.472 s |
  | Frequency | local server | | 0.040 s |

  Every case has zero mistakes. Existing suites unchanged: speed 73/73, search 21/21, drill 36/36, scan markers 4/4.

## Runtime status
- 1.0.4: user-tested in remote missions at speed 5 (`TESTING.md`).
- 1.1.0: Symbols reroll reported working in game by the user (2026-10-14; build, mission and ping not recorded). Search transition skip also reported working (same day). The Frequency pipeline is offline only; the remaining steps are in `TESTING.md` under the 2026-10-14 entry.

## Open items
- 2026-10-14: verify in game that re-interaction succeeds at the first allowed frame on a dedicated server, and measure the Symbols reopen delay (DMF debug: `Symbols reroll` and `Reopen` lines).
- 2026-10-14: seed-predicted openings and exact Symbols lookahead need an in-game check that a client reproduces the server's minigame seeds (NoBrainer's `seed_status`).
