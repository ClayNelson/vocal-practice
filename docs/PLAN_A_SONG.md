# Plan a Song in the App: Design Note

Status: Decided, not built. October 23, 2026

## Decision

- **Build the offline planner first** (option 3 of the three discussed). The app turns a song, a goal, and a date into a dated `plan.json` with plain Swift: no network, no key, no cost. This doubles as the app's showcase mode, which is needed before the Nov 9 phase change in the Pretty Woman plan.
- **Add AI on top, with a key entered in the app.** Clay uses his own Anthropic API key for now. It is typed into Settings and stored in the Keychain. It is never compiled into the build, because anything shipped in a TestFlight build to students can be extracted.
- **Without a key, AI features stay hidden.** Students without a key get the offline planner only.
- **Keep the provider pluggable,** so a studio backend (option 2: one key held server-side, per-student limits) can be added later without changing the app's flow or the plan format.

Options considered and set aside for now:

| Option | Who pays | Why not first |
| --- | --- | --- |
| 1. Bring your own key | Each user | Too much friction for students (Console account, billing, key) |
| 2. Studio key behind a backend | Nicolette or the studio | Needs hosting, limits, and a decision on who owns the bill |
| 3. Offline planner, AI optional | Nobody for the offline part | **Chosen.** Free baseline for everyone; AI where a key exists |

## How it fits together

Every path produces the same `plan.json` defined in [SONG_PLAN.md](SONG_PLAN.md). The app does not care which provider made it.

```
PlanRequest (song, artist, goal, date, key, known range, notes)
        |
        v
PlanProvider (protocol)
  - OfflinePlanner       Swift only. Phases, checkpoints, default sections.
  - ClaudePlanner        Research and judgment from Claude, then the
                         OfflinePlanner builds the dates around it.
  - StudioPlanner        Later: same as ClaudePlanner, via a backend.
        |
        v
SongPlan (plan.json) -> validated in Swift -> saved with the Song
```

**Split of work.** Claude never computes dates: it supplies the research and the judgment. Swift always builds the phases and checkpoints from the goal date, so dates are deterministic, testable, and right even if the model drifts.

| From Claude (ClaudePlanner only) | From Swift (always) |
| --- | --- |
| Song facts, reference version, sources | Phases counted back from the goal date |
| Original key, range, tempo | Phase song blocks (listen, sections, full runs, maintenance, taper) |
| Hard sections with focus lines | Checkpoints (key lock, arrangement lock, confirm date) |
| Honest read and key recommendation | Validation against SONG_PLAN.md rules |
| Questions for the teacher | Holiday and travel weeks as maintenance |

## Offline planner rules

**Inputs:**
- Title, artist, goal type and date (with an "approximate" switch)
- Original key and key options
- Low and high notes, if known
- Minutes per pass
- Blocked weeks (holidays, travel)

**Phase template:** by weeks until the goal.

| Weeks out | Phases |
| --- | --- |
| 10 or more | Listen (2) → Sections: hard spots (3) → Sections: character and story (3) → Full runs (2) → Taper (1); extra weeks extend the section phases |
| 4 to 9 | Listen (1) → Sections (scaled) → Full runs (1 to 2) → Taper (1) |
| Under 4 | Sections → Full runs → Taper (last 3 to 5 days) |

**Other rules:**
- Blocked weeks become maintenance without moving the goal.
- **Checkpoints:**
  - Lock key at the end of Listen.
  - Lock arrangement before Full runs.
  - Confirm date, when the date is approximate.
- **Default sections when offline:** "Hardest phrase" and "Ending," both editable. The user can add more.
- **Range check:** if the known range is set and the song's high note is above it, suggest the lower key options.

## ClaudePlanner

- **One request** to the Anthropic Messages API, with web search enabled. Check docs.claude.com for the current web search tool version and model names when building.
- **System prompt** distilled from the `plan-a-song` skill. Its rules:
  - Research with sources.
  - No lyrics.
  - Name sections by function.
  - Give an honest read, and say what evidence it is based on.
  - Ease over altitude when recommending keys.
- **Structured output:**
  - The response is constrained to the research part of `plan.json` (song, sections, questions, notes), plus a short read and a list of sources.
  - Swift then adds the goal, phases, and checkpoints.
- **Context sent:** only the request fields, plus the user's range history if they allow it in Settings. No takes, no audio, no Trello content.
- **Failures:** if the call fails or the key is invalid, fall back to the OfflinePlanner and say so in one line.
- **Spend control:**
  - The key holder sets a monthly limit in the Anthropic Console.
  - The app shows a rough count of plans made this month.

## Settings

New **AI** section:
- Anthropic API key (Keychain; shown masked; Test button)
- Model (default: the current Sonnet; Opus as an option for deeper research)
- "Send my range history" toggle (default on)
- Footnote: "Your key, your usage. Set a spending limit in the Anthropic Console."

## UI

- **Songs tab, + menu:** "Plan a song." A form for the inputs, then "Make plan."
  - Offline when there's no key.
  - "Research with Claude" when there is one.
- **Result screen:**
  - The read, sources, and key recommendation.
  - Sections and phases, all editable.
  - "Use this plan."
- **Song detail:**
  - Goal countdown.
  - Current phase.
  - Sections with their own takes and free/pressed/cracked ratings.
  - Checkpoints.
  - "Export plan.json" through the share sheet, to save into MyOps.
- **Import:** open a `plan.json` from Files, such as one written by the Claude skill.

## Data model additions

| Entity | Fields |
| --- | --- |
| Song | goalType, goalLabel, goalDate, goalDateIsApprox, originalKey, keyOptions, rangeLow, rangeHigh, planJSON (source of truth, round-trips to export) |
| Section (new) | song, sectionID, title, difficulty, focus, order, lastPracticed |
| Take | sectionID (optional), rating (free, pressed, cracked) |
| Checkpoint (new) | song, title, due, done |
| RangeReading (new) | date, lowNote, highNote |

## Planner changes

- `ShowcasePhase.current(for: date, plan:)`
- The song item in a session follows the phase's `songBlock`:
  - `sections`: the hardest unresolved section among `focusSections`, using the most recent rating.
  - `fullRun`: a full run, at minutes per pass times two.
  - `maintenance`: scheduled only on two or three days a week.
  - `taper`: one short run, skipped when the voice check-in is rough.
- **Tests:**
  - Phase boundaries
  - Section selection
  - Maintenance cadence
  - Taper skip
  - Plan validation (a Swift port of `tools/validate_plan.py`)

## Build order

1. Plan format in Swift: `SongPlan` Codable, validator, import from Files, export.
2. Offline planner and planner phase rules, with tests.
3. Song detail: countdown, phase, sections, checkpoints, section takes.
4. Settings AI section and Keychain key.
5. ClaudePlanner with structured output and fallback.
6. Later: StudioPlanner (backend, per-student limits) if Nicolette wants it for students.

Steps 1 to 3 are the showcase mode; target before Nov 9.

## Open questions

- Should students see a "Plan a song" button with AI disabled, or only the offline planner, labeled plainly?
- Who owns the bill if Nicolette wants AI for students: her, the studio, or bundled into lessons?
- Does the plan sync back to MyOps automatically (needs MyOps sync), or stay export-only?
