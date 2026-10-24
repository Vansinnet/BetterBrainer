# Changelog

All notable user-facing changes to BetterBrainer are recorded here. Format
loosely follows [Keep a Changelog](https://keepachangelog.com/). Validation
details live in `TESTING.md`.

The release workflow publishes the section whose heading matches the pushed
tag (`v1.0.5` uses `## [1.0.5]`) as the GitHub release notes and the Nexus
Mods changelog, so write the section before tagging.

## [1.0.4] - 2026-10-05

### Fixed
- Auspex Scan highlights now clear as soon as the server confirms that an
  object has been scanned, instead of waiting for the next one-second
  refresh.
- Objects stay highlighted while aiming away, during interrupted scans and
  through the client's predicted confirmation. The game's own requested
  outlines are preserved when BetterBrainer releases its marker.

## [1.0.3] - 2026-10-04

### Changed
- Drill plans movement using the game's node-selection rule and the joystick
  values received by the server, reducing unnecessary extra moves.
- At speed 5, Drill and Search send the next stage's first movement during
  the transition, reducing receipt-delay overhead.
- Search and Drill wait for the server to have processed later, timely input
  before submitting, preventing stale movement from causing a wrong press
  during input stalls.
- Drill retries a lost move with direct aim once server state proves that the
  old input cannot run again.
- Search waits for the server to recentre the cursor when reopening a
  terminal, including after a settings change.
- Prediction fallbacks reset at the next mission. Optional DMF debug logging
  records movement and acknowledgement decisions.

### Fixed
- Drill no longer gets stuck on a target at the cursor's starting position.

## [1.0.2] - 2026-10-03

### Changed
- Frequency: removes the fixed 0.5-second opening delay at speed 5.
  Intermediate speeds also start sooner; speed 1 retains its original pacing.
- Decode Search: submits on the first fully confirmed target sample after
  movement at speed 5, saving one input frame.
- Decode Symbols: skips the 120 ms stability wait when a complete fresh board
  has arrived, retaining the initial button release and 30 ms safe hit
  margin.
- Auto-scan: after an interrupted scan, a different eligible target can start
  immediately when normal scan mode resumes. Same-target retry protection
  remains.

## [1.0.1] - 2026-09-10

### Fixed
- Balance uses gameplay time consistently for position samples and
  corrections, so fresh network updates no longer briefly release automatic
  steering during fixed-step input.

## [1.0.0] - 2026-09-08

### Changed
- Decode Symbols uses the available hit window on every stage, retaining a
  30 ms margin inside the engine's strict target boundaries. This allows
  earlier presses and catches valid late opportunities instead of waiting for
  another sweep.

### Removed
- Removed Smart Seed Reroll, including seed prediction, retry decisions,
  automatic terminal reinteraction, its setting, localization and runtime
  hooks.
