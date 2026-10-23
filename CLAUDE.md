# CLAUDE.md

Guidance for Claude Code in this repository.

## What this is

Vocal Practice: a personal iOS app (SwiftUI, SwiftData, iOS 17+) that turns a teacher's lessons into a daily practice routine. Owner: Clay Nelson. Distributed only through TestFlight: Clay, his teacher Nicolette, and her students.

Read before changing behavior:
- `docs/SPEC.md`: what the app does and the current state of each area
- `docs/IMPLEMENTATION_PLAN.md`: the active build (milestones M0, M1, M2) with acceptance criteria
- `docs/SONG_PLAN.md`: the `plan.json` format shared with Clay's `plan-a-song` Claude skill and MyOps
- `docs/PLAN_A_SONG.md`: design decisions for AI song planning

## Build and test

- **The Xcode project is generated.** Run `xcodegen generate` from `project.yml`, and never commit `VocalPractice.xcodeproj`. Add files under `VocalPractice/` or `Tests/` and XcodeGen picks them up.
- **Tests:** run with `xcodebuild test -project VocalPractice.xcodeproj -scheme VocalPractice -destination 'platform=iOS Simulator,name=iPhone 16'`, or Cmd+U in Xcode.
- **Without macOS or Xcode** (for example in a Linux sandbox), you cannot compile:
  - Keep logic in Foundation-only files, and rely on CI (`.github/workflows/ci.yml`, added in M0) to build and test.
  - Read neighboring code closely, and match the APIs it already uses.
- **TestFlight:** `.github/workflows/testflight.yml`, run manually from the Actions tab. It runs the tests, then archives and uploads.

## Conventions

- **Pure logic stays pure.**
  - The planner (`Planner/`), Trello mapping (`Trello/TrelloMapping.swift`), pitch detection (`Pitch/PitchDetector.swift`), and plans (`Plans/`, M1) use Foundation only: no SwiftUI, SwiftData, or networking.
  - Views and SwiftData models call into them through snapshots.
  - New logic goes the same way, with unit tests.
- **SwiftData migrations:** every new model property must be optional or have a default. Existing installs carry real practice history; never lose it.
- **Dates in plans:** calendar days (`PlanDate`), not `Date` in UTC. Test across DST and year boundaries.
- **Secrets and credentials:**
  - Never commit keys or tokens.
  - The Trello API key arrives via the `TRELLO_API_KEY` build setting (a repo secret).
  - Per-person credentials (Trello token, Anthropic key) are entered on the device and stored with the `Keychain` helper.
  - Never compile a personal key into the app.
- **Trello is read-only.** Sync never writes to Trello and never deletes local data.
- **No lyrics.** Never put song lyrics in code, fixtures, tests, prompts, or docs. Name song sections by function ("Top phrases", "Bridge climb").
- **Writing style for docs and user-facing strings:** no em dashes. Use commas, colons, or separate sentences. Plain, direct copy.
- **Commits:** small and descriptive. Branch per milestone, PR to main, CI green before merge.

## Layout

```
VocalPractice/
  App/        entry, tabs, onboarding sheet, Prefs keys
  Planner/    SessionPlanner, WeeklyProgress (pure, tested)
  Models/     SwiftData models, sample seed content
  Pitch/      YIN detector, live tracker, pitch screen
  Trello/     sign-in, read-only client, pull sync, onboarding views
  Services/   audio playback, take recording, reminders
  Views/      Today, session player, history, warmups, songs, lessons, settings
  Plans/      (M1) SongPlan format, validator, offline planner, plan store
  AI/         (M2) ClaudePlanner and prompt
Tests/        unit tests for the pure layers
docs/         spec, plan format, design notes, implementation plan, examples
tools/        validate_plan.py
web/          Trello sign-in relay page
```

## Related repo

MyOps (`ClayNelson/MyOps`) holds song folders under `songs/covers/<song>/`, including `plan.json` files written by the `plan-a-song` skill. The Pretty Woman plan there is the reference example for M1.
