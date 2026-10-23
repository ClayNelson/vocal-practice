# Song Plan Format

Status: Draft v1, October 23, 2026

A song plan is the bridge between the "plan a song" intelligence and the app. Phase 1: a Claude skill researches the song and writes `plan.json` into the song's MyOps folder. Phase 2: the app imports it (Files, then MyOps sync) and the planner follows its phases. Later, an in-app "Plan a song" button produces the same file through a small backend, so students get it too.

The file is `plan.json` in the song folder, for example `songs/covers/oh-pretty-woman-roy-orbison/plan.json`. Human notes stay in that folder's README, chords, and notes files; `plan.json` holds only what the app acts on.

## Fields

| Field | Type | Notes |
| --- | --- | --- |
| `schemaVersion` | int | `1` |
| `song.title`, `song.artist` | string | |
| `song.reference` | string | The recording to study |
| `song.originalKey` | string | e.g. `A` |
| `song.keyOptions` | [string] | Keys under consideration, first is the current pick |
| `song.range.low`, `song.range.high` | string | Scientific pitch in the original key, e.g. `E3`, `F#4` |
| `song.tempoBPM` | int? | |
| `song.minutesPerPass` | int | Practice minutes per pass (song length plus a reset) |
| `goal.type` | string | `showcase`, `recording`, `lesson`, or `none` |
| `goal.label` | string | Shown on Today, e.g. "Vocal showcase" |
| `goal.date` | date | `YYYY-MM-DD` |
| `goal.dateIsApprox` | bool | True until the real date is known |
| `sections` | [Section] | The hard parts worth isolating |
| `phases` | [Phase] | Contiguous, in order, ending on the goal date |
| `checkpoints` | [Checkpoint] | Dated decisions |
| `questionsForTeacher` | [string] | Feeds the pre-lesson brief |
| `myOpsPath` | string | Song folder in MyOps |
| `generatedBy`, `generatedAt` | string | Provenance |

**Section:** `id` (kebab-case), `title`, `difficulty` (`high`, `medium`, `low`), `focus` (one line on what to work on).

**Phase:** `id`, `title`, `start`, `end` (inclusive dates), `songBlock`, `focusSections` (section ids), `notes`.

`songBlock` tells the planner what the song item is during the phase:

| Value | Song item in a session |
| --- | --- |
| `listen` | Listening and speaking in rhythm; no full-voice singing required |
| `sections` | The hardest unresolved section from `focusSections`, recorded as its own take |
| `fullRun` | Full passes, start to finish |
| `maintenance` | Full passes on two or three days a week only |
| `taper` | One short run; skipped when the voice check-in is rough |

**Checkpoint:** `title`, `due` (date), `done` (bool).

## Rules a plan must follow

- Phases cover every day from the first phase start to the goal date, with no gaps or overlaps.
- The last phase is `taper` and ends on the goal date.
- Section ids referenced by phases exist.
- No lyrics. Section titles name the spot ("Top phrases", "Bridge climb"), not the words.
- Approximate goal dates are flagged, not guessed silently.

## Example

See `songs/covers/oh-pretty-woman-roy-orbison/plan.json` in MyOps.
