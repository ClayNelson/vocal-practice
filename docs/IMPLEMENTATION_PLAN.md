# Implementation Plan: Song Plans, Showcase Mode, and Plan a Song

Status: Ready to build, October 23, 2026
Read first: [SPEC.md](SPEC.md) (what), [SONG_PLAN.md](SONG_PLAN.md) (format), [PLAN_A_SONG.md](PLAN_A_SONG.md) (design and decisions), repo `CLAUDE.md` (conventions).

## Outcome

A song can carry a dated plan toward a goal. The daily session follows the plan's current phase, and practice is tracked per section. Plans come from three places: an imported `plan.json`, the app's own offline planner, or (M2) Claude research using an Anthropic key the user enters.

**Deadline that matters:** M1 on TestFlight before **November 9, 2026**. That's when Clay's Pretty Woman plan moves from "listen" into "sections."

## Milestones

| Milestone | Scope | Ship |
| --- | --- | --- |
| M0 | CI test workflow | First PR |
| M1 | Plan format in Swift, persistence, offline planner, planner integration, UI | TestFlight before Nov 9 |
| M2 | Settings AI key, range history, ClaudePlanner | After M1 is in use |

Work on a branch per milestone, open a PR, keep CI green, then run the TestFlight workflow from main.

---

## M0: CI tests on every push

The only existing workflow is TestFlight (manual, uploads a build). Add `.github/workflows/ci.yml`:

- **Triggers:** push to any branch, and pull requests.
- **Runner:** `macos-15`, using the same project generation and `xcodebuild test` steps as `testflight.yml`.
- **What it skips:** signing, secrets, and upload.

**Done when:** a push runs the existing tests (SessionPlanner, PitchDetector, TrelloMapping) and they pass.

---

## M1: Song plans and showcase mode

### M1.1 Plan format in Swift

New folder `VocalPractice/Plans/`. Keep all of it Foundation-only, with no SwiftUI or SwiftData, so it is unit testable.

**`SongPlan.swift`:** Codable types that match SONG_PLAN.md field for field.

- **Top-level types:** `SongPlan`, `PlanSong`, `PlanRange`, `PlanGoal`, `PlanSection`, `PlanPhase`, `PlanCheckpoint`.
- **`SongBlock`:** a String enum of `listen`, `sections`, `fullRun`, `maintenance`, and `taper`.
- **`GoalType`:** a String enum of `showcase`, `recording`, `lesson`, and `none`.
- **`PlanDate`:** a calendar-day type (year, month, day) that decodes and encodes `"YYYY-MM-DD"`.
  - Compare dates by day, never through `Date` in UTC. Off-by-one errors in phases are the main risk.
  - Give it helpers to convert to and from `Date` in a given `Calendar`, plus `adding(days:)` and `daysUntil(_:)`.
- **Encoding:** sorted keys and pretty printing, so exports diff cleanly in MyOps.
- **Schema additions.** These are all optional and needed by M1 and M2. Update SONG_PLAN.md and `tools/validate_plan.py` to match:
  - `assessment`: an optional object.
    - `summary`: the honest read, one paragraph.
    - `keyRecommendation`: string.
    - `sources`: an array of `{ title, url }`.
  - `phase.notes`: already in the schema; it is optional in Swift.
  - `blockedRanges`: an optional array of `{ start, end, label }`, recording why a maintenance phase exists.

**`PlanValidator.swift`:** a port of `tools/validate_plan.py` that returns `[String]` errors. It enforces the same rules:

- `schemaVersion` is 1.
- Required song fields are present.
- Range notes parse.
- The goal type is valid.
- Section difficulties are valid.
- Phases are contiguous, with no gaps or overlaps.
- Each phase's `songBlock` is valid.
- Every focus section exists.
- The last phase is a taper and ends on the goal date.

Run it on import and before saving.

**`NoteName.swift`:** parse `"F#4"`, `"F♯4"`, `"Bb3"`, and `"E♭3"` into MIDI numbers. Format with the existing `Note.label(midi:)`, which uses ♯ and ♭.

**Tests (`Tests/SongPlanTests.swift`):**
- Decode the Pretty Woman example. Embed the JSON from MyOps `songs/covers/oh-pretty-woman-roy-orbison/plan.json` as a string literal; it has 6 phases and a goal of 2027-01-25.
- Check that encoding then decoding round-trips.
- Give each validator rule one failing case.
- Note parsing: E3 is 52, F#4 is 66, Bb3 is 58, and C4 is 60.
- `PlanDate` arithmetic across the Dec/Jan boundary and the March DST change.

### M1.2 Persistence

**Models** (add to `Models.swift`, and register in the schema in `VocalPracticeApp.swift`). Every new property is optional or has a default, because existing installs must migrate.

- **`Song` gets new fields:**
  - `planJSON: String?`: the source of truth.
  - Mirrored fields for queries and display: `goalType: String?`, `goalLabel: String?`, `goalDate: Date?`, `goalDateIsApprox: Bool = false`, `originalKey: String?`, `keyOptionsRaw: String = ""`, `rangeLowMidi: Int?`, `rangeHighMidi: Int?`.
  - Relationships to `sections: [SongSection]` and `checkpoints: [Checkpoint]`, both with cascade delete.
- **`SongSection` (new):**
  - Plan fields: `sectionID`, `title`, `difficulty`, `focus`, `order`.
  - Practice fields: `lastPracticed: Date?` and `lastRating: String?`, where the rating is `free`, `pressed`, or `cracked`.
  - Back-reference: `song`.
- **`Checkpoint` (new):** `title`, `due: Date`, `done: Bool`, and `song`.
- **`Take` gets new fields:** `sectionID: String?` and `rating: String?`.

**`PlanStore.swift`** (MainActor; it is the only place that writes plan data):

- **`apply(_ plan: SongPlan, to song: Song)`:**
  1. Validate first.
  2. Write `planJSON` and the mirrored fields.
  3. Sections: upsert by `sectionID`. Keep `lastRating` and `lastPracticed`, and update title, focus, difficulty, and order. Delete sections no longer in the plan, along with their ratings; their takes stay.
  4. Checkpoints: replace them, carrying `done` forward by matching title.
  5. If the song's key is empty, set it from `keyOptions.first`.
  6. Set `showcase = true` when `goalType == .showcase`.
- **`currentPlan(for:)`:** decodes `planJSON`.
- **`exportPlan(for:)`:** builds a `SongPlan` from `planJSON`, with checkpoint `done` states and section edits written back in.
- **`removePlan(from:)`:** clears the plan fields, sections, and checkpoints, and keeps the song and its takes.
- **Import from Files:**
  - Open a `.json`, decode it, and validate it.
  - Match it to an existing song by normalized title and artist; otherwise create the song. Reuse `TrelloMapping.normalize`.
  - Show validator errors plainly; never half-apply a plan.

### M1.3 Offline planner

**`VocalPractice/Plans/OfflinePlanner.swift`:** pure and deterministic.

```swift
struct PlanRequest {
    var title: String, artist: String
    var goalType: GoalType, goalLabel: String, goalDate: PlanDate, goalDateIsApprox: Bool
    var start: PlanDate                      // default: today
    var originalKey: String?, keyOptions: [String]
    var rangeLow: String?, rangeHigh: String?
    var minutesPerPass: Int                  // default 6
    var sections: [PlanSection]              // empty means defaults
    var blocked: [(start: PlanDate, end: PlanDate, label: String)]
    var questionsForTeacher: [String]
    var assessment: PlanAssessment?          // M2 fills this
    var userHighMidi: Int?                   // from range history (M2), optional
}
enum OfflinePlanner { static func makePlan(_ r: PlanRequest) -> SongPlan }
```

**Phase allocation.** Let D be the number of days from `start` to `goalDate`, inclusive.

| D | Phases, in order |
| --- | --- |
| 70 or more | `listen` 14 ("Absorb and key") → `sections` "Build the hard spots" → `sections` "Character and story" → `fullRun` 14 ("Performance mode") → `taper` 7. The two section phases split the remainder, with the first getting any odd day. |
| 28 to 69 | `listen` 7 → `sections` "Build the hard spots" (the remainder) → `fullRun` (7 if D is under 49, else 14) → `taper` 7 |
| 7 to 27 | `sections` (the remainder) → `fullRun` (the larger of 3 and D/4, rounded down) → `taper` 3 |
| 2 to 6 | `fullRun` (D minus 1) → `taper` 1 |
| 1 | `taper` 1 |

**Blocked ranges** (holidays, travel):
- The part of a blocked range that overlaps a non-taper phase becomes its own `maintenance` phase, splitting that phase.
- The block uses up those days; nothing moves later.
- A block never touches the taper.
- Drop zero-length phases.
- Merge two adjacent maintenance phases into one.
- A non-maintenance remnant shorter than 3 days that sits next to a maintenance phase joins that maintenance phase.

**Sections:**
- **Defaults** when the request has none: `hardest-phrase` "Hardest phrase" (high) and `ending` "Ending" (medium).
- **Focus by phase:**
  - "Build the hard spots" focuses the high-difficulty sections, or all sections if none is high.
  - "Character and story" and single section phases focus all sections.

**Checkpoints:**
- **Lock key:** the last day of `listen`, or `start` plus 3 days when there is no listen phase.
- **Lock arrangement:** the day before the first `fullRun`.
- **Confirm date** (only when the date is approximate): `start` plus 14 days, or the day before the taper if that comes sooner.
- **Ordering:** sort checkpoints by date, and drop any that fall before `start`.

**Range check:** when `rangeHigh` and `userHighMidi` are both known and the song's high note is above the user's high note:
- Set `assessment.keyRecommendation` to something like: "The top note F#4 is 1 semitone above your recent high. Try Ab or G."
- Lower key suggestions come from shifting `originalKey` down by that many semitones, then one more.
- Never overwrite an assessment that M2 supplied.

**Notes per phase:** short default text, taken from the Pretty Woman plan in tone. For example, "Daily listening to the reference. Map breath points. Speak in rhythm. Test keys."

**Tests (`Tests/OfflinePlannerTests.swift`):**
- **Every output passes `PlanValidator`.** Run this property-style check over D from 1 to 150, with and without a blocked range.
- **Golden test:** start 2026-10-26, goal 2027-01-25 (D = 92), approximate, blocked 2026-12-21 to 2027-01-03. Expected phases, exactly:

  | # | Block | Title | Dates |
  | --- | --- | --- | --- |
  | 1 | listen | Absorb and key | Oct 26 to Nov 8 (14 days) |
  | 2 | sections | Build the hard spots | Nov 9 to Dec 7 (29) |
  | 3 | sections | Character and story | Dec 8 to Dec 20 (13; the block took Dec 21 to Jan 3, and the 1-day Jan 4 remnant joined the maintenance phase) |
  | 4 | maintenance | Holiday maintenance (block label) | Dec 21 to Jan 4 (15) |
  | 5 | fullRun | Performance mode | Jan 5 to Jan 18 (14) |
  | 6 | taper | Taper | Jan 19 to Jan 25 (7) |

  Expected checkpoints: Lock key Nov 8, Confirm date Nov 9, Lock arrangement Jan 4.
- **Blocks:** a block inside the taper leaves the taper unchanged.
- **Defaults:** default sections appear when none are given, and focus sections follow the difficulty rule.
- **Range:** the range check produces a recommendation only when it should.

### M1.4 Session planner integration

Extend `SessionPlanner` (pure) without breaking the existing tests.

- **`SongSnapshot` gains:** `goalDate: Date?` and `planContext: SongPlanContext?`. Both default to nil, so existing call sites and tests compile unchanged.
- **`SongPlanContext`** carries:
  - The current phase's `songBlock`
  - `minutesPerPass`
  - The phase's focus sections as `[SectionSnapshot]`, where each is `(id, title, focus, difficulty, lastRating, lastPracticed)`
  - `fullRunsThisWeek: Int`
- **`PhaseResolver.current(plan:on:calendar:)`:** a pure function returning the phase that contains the day, or nil before the first phase and after the goal. Song.snapshot builds the context from `planJSON`, the sections, and the takes.
- **Ordering** (replacing the showcase-first rule):
  1. Songs with an active plan, nearest goal date first.
  2. Other showcase-flagged songs.
  3. Songs in Learning.
  4. Least recently practiced.
- **`PlanItem.song` carries a `SongMode`:**

| Phase block | Mode | Minutes | Notes |
| --- | --- | --- | --- |
| none / unplanned | `.normal` | song.minutes | |
| `listen` | `.listen` | minutesPerPass | |
| `sections` | `.section(id, title, focus)` | minutesPerPass | Pick: lastRating `cracked`, then `pressed`, then never practiced, then oldest `lastPracticed`. Ties go to difficulty high, then medium, then low, then plan order. |
| `fullRun` | `.fullRun` | minutesPerPass × 2 | |
| `maintenance` | `.fullRun` if `fullRunsThisWeek < 3`, else the song is omitted | minutesPerPass | |
| `taper` | `.taper` | minutesPerPass | Omitted when voiceCondition ≤ 2 |

- **Rough voice still halves the song budget.** If a planned song's item doesn't fit the halved budget, it is still included first (the existing `fill` rule).

**Tests (extend `SessionPlannerTests.swift`):**
- Phase boundary days.
- Section pick order.
- The maintenance cap.
- Taper skipped on a rough voice.
- A planned song orders ahead of a showcase-flagged unplanned song.
- An unplanned song's behavior is unchanged.

### M1.5 UI

**Today:**
- A goal card above the session, showing the nearest active goal:
  - "Vocal showcase · 13 weeks, 3 days" (with "about" if the date is approximate)
  - The current phase title
  - The next open checkpoint with its due date; overdue ones in orange
- Tap goes to the song.
- Song rows in the plan show the mode: "Section: Top phrases", "Full run", "Listen", or "Taper run".

**Session player:**
- For `.section`, show the section title and focus line under the song title.
- After a take on a section, ask "How did it feel?" with three buttons: Free, Pressed, and Cracked. They are skippable.
- Save `sectionID` and `rating` on the `Take`, and update `SongSection.lastRating` and `lastPracticed`.
- For `.listen`, show the reference and the phase notes; recording is optional.

**Song detail** (new Plan section):
- **Without a plan:** buttons for "Make a plan" and "Import plan."
- **With a plan:**
  - Goal and countdown
  - A phase timeline, with the current phase highlighted
  - Sections with their last rating and take count; a tap filters the takes list
  - Checkpoints as toggles
  - An assessment and sources when present (M2)
  - Actions: Export plan (share sheet, `<title-kebab>.plan.json`), Edit plan, Remove plan (with a confirm)

**Make a plan form** (offline):
- **Goal:** type, label, date, and an "approximate" toggle.
- **Song:** original key, key options, and range low and high, as note pickers or text validated with NoteName.
- **Practice:** minutes per pass, sections (add, remove, reorder, difficulty), blocked ranges, and teacher questions.
- **Result:** the form shows a preview of the phase timeline, then a Save button. M2 adds a "Research with Claude" button to this same form.

**Edit plan:**
- Edit sections, checkpoints, the goal date, and blocked ranges.
- Changing the date or blocks re-runs the OfflinePlanner phase allocation, keeping sections, questions, and assessment.

**Import:** a `fileImporter` for `.json`, also on the Songs toolbar, going through `PlanStore`.

### M1.6 Sample content and docs

- **Sample content:** Settings, Sample content also attaches the Pretty Woman plan to the seeded Pretty Woman song. Embed the JSON, via `PlanStore.apply`.
- **README:** add a "Song plans" section covering how to make, import, and export a plan, and the plan-a-song skill.
- **SPEC:** update the Current state table.

### M1 acceptance

On Clay's phone, after a TestFlight install:

1. Import `oh-pretty-woman-roy-orbison/plan.json` from Files. The song shows the goal card, six phases, four sections, and three checkpoints.
2. On Oct 26 to Nov 8, Today shows Pretty Woman as "Listen."
3. On or after Nov 9, Today shows "Section: Top phrases" or "Section: Bridge climb," following ratings.
4. Rating a section take "free" moves the next session to the other focus section.
5. Export produces a `plan.json` that passes `tools/validate_plan.py`, with checkpoint `done` states preserved.
6. Make a plan with no network yields a valid plan with sensible phases for 1, 20, 45, and 92 days out.
7. Existing data (warmups, songs, takes, lessons, Trello) survives the upgrade.

---

## M2: Plan a song with Claude

Design and decisions are in [PLAN_A_SONG.md](PLAN_A_SONG.md). The key is entered in the app and kept in the Keychain. It is never compiled in, and the AI features stay hidden without it.

### M2.1 Settings: AI

- **Key field:** an Anthropic API key in a `SecureField`, saved through the existing `Keychain` enum (account `anthropic-key`), shown masked, with a Remove button.
- **Test button:** a minimal Messages API call that reports "Key works" or the API's error message.
- **Model:** a picker with a free-text override. Defaults: the current Sonnet for planning, Opus as the deeper option. Check docs.claude.com for current model IDs when building; do not hard-code from memory.
- **"Send my range history" toggle:** default on.
- **Plans this month:** a count kept in UserDefaults, with a footnote: "Your key, your usage. Set a monthly limit in the Anthropic Console."

### M2.2 Range history

- **New `RangeReading` model:** `date`, `lowMidi`, and `highMidi`.
- **Pitch screen:** a "Save range" button stores the sitting's range.
- **`RangeHistory.recentHigh(days: 30)`:** the 90th-percentile high over that window, or nil. It feeds `PlanRequest.userHighMidi`.

### M2.3 ClaudePlanner

**`VocalPractice/AI/ClaudePlanner.swift`:** uses URLSession directly, with no SDK dependency.

- **Request:** one Messages API call with Anthropic's server-side web search tool enabled (current tool version per docs.claude.com) and a request timeout of at least 120 seconds.
- **Output:** constrain it to a JSON schema for the research part only. Use the API's structured-output support if available; otherwise a single forced tool call whose input schema is the shape below. Check docs.claude.com for the current mechanism.

```json
{
  "song": { "reference", "originalKey", "keyOptions", "range": { "low", "high" }, "tempoBPM", "minutesPerPass" },
  "sections": [ { "id", "title", "difficulty", "focus" } ],
  "questionsForTeacher": [ "..." ],
  "assessment": { "summary", "keyRecommendation", "sources": [ { "title", "url" } ] },
  "constraintCheck": { "question", "answer", "source" }   // optional, e.g. "has it been in a film or TV show?"
}
```

- **Merge:** fill a `PlanRequest` from the response, then call `OfflinePlanner.makePlan`. Claude never sets dates or phases.
- **Context sent:** title, artist, goal type and label, goal date, the user's note, and, if allowed, the recent high and low as note names. Never send takes, audio, Trello data, or lesson notes.
- **Failure:** on timeout, a non-2xx status, or a parse or validation failure, fall back to `OfflinePlanner` with the user's inputs and show one line: "Couldn't reach Claude, made an offline plan." A 401 means "Check your API key in Settings."
- **UI:** "Research with Claude" on the Make a plan form, with a progress state ("Researching the song...") and a Cancel button. The result screen shows the assessment, sources (tappable), and key recommendation above the phase preview.
- **Copyright:** the system prompt forbids lyrics. As a backstop, the app strips any section `title` or `focus` longer than 120 characters.

**System prompt** (`VocalPractice/AI/PlanPrompt.swift`), distilled from the plan-a-song skill:

> You help a singer prepare a song for a dated goal. Research the song with web search and cite sources. Return only the JSON the schema asks for.
> Song facts: the writers and release only as needed for the summary; the best reference recording to study (often a live version); original key, tempo, and the sung range in scientific pitch notation (male vocals written in treble clef sound an octave lower).
> Sections: two to five hard spots, named by musical function ("Top phrases", "Bridge climb", "Ending"), never by lyrics. Each gets a difficulty (high, medium, low) and one line of practice focus.
> Assessment: an honest read of what makes the song hard and where it sits for this singer, given any range data provided. Say plainly what the read is based on and that it is not a hearing. Recommend a key: test the original first, then one or two lower options. Prefer ease over altitude, and singing in the singer's own voice over imitating the original timbre.
> Questions for the teacher: three to five, specific to this song.
> Never reproduce lyrics, not even a line.
> If the user states a constraint (for example "must have been in a film or TV show"), check it and report the answer with a source in constraintCheck.

**Tests (`Tests/ClaudePlannerTests.swift`), with no network:**
- Parse a canned response.
- Merge it into the request, and check the resulting plan validates.
- A malformed response falls back to the offline plan.
- A 401 maps to the key error.
- The lyric-length backstop strips long titles.
- The request body contains no take or Trello data.

### M2 acceptance

1. With no key, there's no AI button anywhere, and Make a plan works offline.
2. With Clay's key, "Research with Claude" for a new song returns a plan with sources, sections, an assessment, and a key recommendation, and it validates. Phases match what the offline planner makes for the same dates.
3. Airplane mode or a bad key produces an offline plan with a one-line explanation, never a dead end.
4. The plans-this-month count increments.

---

## Out of scope for these milestones

- Singing Carrots web exercises
- MyOps sync (export and import through Files covers it for now)
- Lesson capture
- Native pitch exercises
- The studio backend (StudioPlanner)
- Pre-lesson brief
- App Store release

## Risks and notes

- **Day math:** do all of it in `PlanDate` and a single `Calendar`. Test across DST and year boundaries.
- **SwiftData migration:** after adding models, install over the existing TestFlight build once before handing it to students.
- **Plan edits vs. imports:** importing over an existing plan replaces it, but keeps section ratings that match by `sectionID`. Say so in the confirm dialog.
- **Web search latency:** keep the UI responsive, cancellable, and honest about waiting.
