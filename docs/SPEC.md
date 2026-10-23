# Vocal Practice: Spec

Owner: Clay Nelson
Status: v1.2 draft, October 23, 2026 (v1 drafted October 7; v1.1 Trello sync added October 23)

Implementation plan for the next build: [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md).

## Problem

Clay takes weekly lessons with Nicolette Holman (Mesmerize Studio). Her warmups arrive as audio tracks on a Trello board, and his songs live in MyOps. Practice happens, but nothing queues it, tracks it, or shows progress, and nothing connects a performance goal (a showcase in January) to what gets practiced today. The studio policy asks for 3 to 5 practice days a week, split half warmups and half songs.

The app makes that routine automatic, works toward dated goals, and is simple enough for Nicolette to give to her students through TestFlight.

## Users

| User | How they get the app | What they have |
| --- | --- | --- |
| Clay | TestFlight (internal) | Trello board, MyOps, his own Anthropic API key |
| Nicolette | TestFlight (external group) | Her students' boards |
| Nicolette's students | TestFlight (external group) | Their own Trello account and lesson board. No API key. |

No App Store release, no accounts or backend of our own. Every per-person credential (Trello token, Anthropic key) is entered on the device and kept in the Keychain. Nothing personal is compiled into the build.

## Goals

1. Open the app, tap Start, and get today's session already built.
2. Hit the weekly practice target the teacher sets (3 to 5 days).
3. Know where every song stands and what to work on next.
4. Work toward a dated goal (showcase, recording, lesson) with a plan that changes what each session practices as the date approaches.
5. Hear improvement over time.

## Current state

| Area | Status |
| --- | --- |
| Session planner (half warmups, half songs, ladders, voice check-in) | Built, tested |
| Session player, takes, solid flags | Built |
| Warmups, Songs, Lessons, Settings, reminders | Built |
| Pitch screen (YIN detector, live note, range for the sitting) | Built, tested |
| Trello sign-in, pull sync, onboarding (v1.1) | Built, tested (mapping); awaiting first TestFlight run |
| TestFlight from GitHub Actions | Built |
| Song plans and showcase mode | **Next build:** milestone M1 |
| Plan a song with Claude | **After M1:** milestone M2 |
| Singing Carrots web exercises | Designed (see Exercise sources), not built |
| MyOps sync, lesson capture, native pitch exercises | Later |

## Core loop

1. **Remind:** a notification on each scheduled practice day at a chosen time.
2. **Plan:** the session planner fills the chosen length (30, 45, or 60 min): first half warmups, second half songs. Songs with a plan follow their current phase (M1).
3. **Practice:** the player runs each item in order. It plays the teacher's track for warmups, shows key, notes, and the current section for songs, and records a take of each.
4. **Log:** at the end of a session, rate voice condition (1 to 5), mark items solid, rate sections (free, pressed, cracked), and add a note.
5. **Review:** weekly progress against target; per-item and per-section take history.

## Session planner rules

**Session length:** a user choice of 30, 45, or 60 minutes. The default comes from the weekly plan: 3 days uses 60, 4 uses 45, 5 uses 30.

**Warmup half:**
- **Ladders:** a ladder warmup (Breath fire starter 125, 150, 175, 200, and so on) contributes only its current rung, the lowest level not yet marked solid. Precursor comes first until marked solid.
- **Standalone warmups** rotate by least recently practiced.
- **Filling:** fill until the warmup half is used; never split an item.

**Song half:**
- **Eligible statuses:** learning, polishing, and performance ready. Seams and retired songs are excluded.
- **Order:** songs with an active goal first (nearest goal date first), then other showcase-flagged songs, then learning, then least recently practiced.
- **Planned songs (M1):** for a song with a plan, the song item follows the current phase. See Song plans.

**Rough voice:** a voice condition of 1 or 2 at check-in halves the song block, drops ladders one rung, and skips taper runs.

## Song plans (M1)

A song plan ties a song to a dated goal. The format is [SONG_PLAN.md](SONG_PLAN.md) (`plan.json`). There's a validator in `tools/validate_plan.py` and a worked example in MyOps at `songs/covers/oh-pretty-woman-roy-orbison/plan.json`.

**What a plan contains:**
- **Goal:** type (showcase, recording, lesson), label, date, and an "approximate" flag.
- **Song facts:** original key, key options, range, minutes per pass.
- **Sections:** the hard spots, each with a difficulty and a focus line.
- **Phases:** contiguous date ranges ending on the goal date, each with a song block.
- **Checkpoints:** dated decisions such as key lock and arrangement lock.
- **Questions for the teacher.**

**Song block by phase:**

| Song block | Song item in a session |
| --- | --- |
| `listen` | A listening and rhythm item (shows reference, notes); a take is optional |
| `sections` | The hardest unresolved section among the phase's focus sections: most recent rating pressed or cracked first, then never practiced, then least recent |
| `fullRun` | A full run at minutes per pass times two |
| `maintenance` | A full run on at most 3 days per week (Monday-start weeks); otherwise the song is skipped |
| `taper` | One short run at minutes per pass; skipped on a rough voice |

Before the first phase and after the goal date, the song behaves as an unplanned song.

**Where plans come from:**
1. **Import:** a `plan.json` from Files, for example one written by Clay's `plan-a-song` Claude skill into MyOps.
2. **The offline planner** in the app (M1): song, goal, and date in; phases and checkpoints out. No network, no key.
3. **Claude research** in the app (M2): adds song facts, sections, an honest read, and teacher questions. It needs an Anthropic key entered in Settings. Design: [PLAN_A_SONG.md](PLAN_A_SONG.md).

Every source produces the same format, and plans export back out as `plan.json`.

## Exercise sources

Every warmup item has a source type, so the queue never depends on where an exercise lives.

| Source type | What the player does | Status |
| --- | --- | --- |
| Track | Plays the teacher's audio file and records a take | Built |
| Web | Opens a saved Singing Carrots exercise in an in-app web view; on close, logs the session and asks "mark solid?" | Designed, not built |
| Native | A built-in pitch exercise using the app's own pitch detector | Later |

**Web source design (not built):**
- **Stored fields:** title, a singingcarrots.com URL, and estimated minutes. Added by pasting a link.
- **Rendering:** a `WKWebView` wrapped for SwiftUI.
- **Microphone:** a `WKUIDelegate` grants media capture for singingcarrots.com only.
- **Login:** a persistent `WKWebsiteDataStore` keeps the user signed in.
- **Navigation:** links outside singingcarrots.com open in Safari.
- **Results:** completion is logged when the view closes; scores are not read from the page.
- **Distribution:** TestFlight only, with each person using their own login. Remove before any App Store release.

## Trello sync (v1.1, built)

- **Sign-in:** each person signs in with their own Trello account through Trello's authorize page (read scope, no expiry).
  - The token lives in the Keychain.
  - The app's Power-Up API key is set at build time from the `TRELLO_API_KEY` repo secret.
  - Sign-in returns through a hosted relay page (`web/trello-callback.html`, set with the `TRELLO_RETURN_URL` repo variable). Without one, the user pastes the token Trello shows.
- **Onboarding:** picks the lesson board, the Warmups list, and the lesson package card. All three can be changed in Settings.
- **Sync** is pull-only:
  - Cards become warmups; ladder rungs are parsed from names like "BFS to 200".
  - Audio attachments become tracks, re-downloaded only when the attachment changes.
  - Package card lines like "4. 10/16" become lessons, and "30 Classes" sets the package size.
  - Nothing is written to Trello, and nothing local is deleted.
- **When it runs:** on launch when the last sync is more than 6 hours old, on pull to refresh in Warmups, and with Sync now in Settings. Only one sync runs at a time.
- **Sample content:** Clay's seed content loads only from Settings, Sample content.

## Data model

| Entity | Fields | Notes |
| --- | --- | --- |
| Warmup | title, ladder group, ladder level, minutes, audio file, solid flag, last practiced, source, trelloCardID, trelloAttachmentID | |
| Song | title, artist, key, status, minutes, lyrics, notes, MyOps path, showcase flag, last practiced | M1 adds the plan fields below |
| Song (M1) | planJSON, goalType, goalLabel, goalDate, goalDateIsApprox, originalKey, keyOptions, rangeLowMidi, rangeHighMidi | planJSON is the source of truth; the other fields are mirrored for queries and display |
| SongSection (M1) | song, sectionID, title, difficulty, focus, order, lastPracticed, lastRating | |
| Checkpoint (M1) | song, title, due, done | |
| PracticeSession | date, planned minutes, completed item ids, voice condition, notes | |
| Take | session, item id, item title, audio file, date | M1 adds sectionID and rating |
| Lesson | date, number, notes, gifted flag | |
| RangeReading (M2) | date, low midi, high midi | Saved from the pitch screen |
| Settings | days per week, reminder time and days, package size, Trello choices, AI key (M2, Keychain) | |

**Status pipeline:** seam, learning, polishing, performance ready, recorded, retired.

**SwiftData migrations:** new properties must be optional or have defaults, so existing installs migrate without loss.

## Screens

1. **Today:** weekly ring, voice check-in, session length, the planned session, and a Start button. M1 adds a goal card for the nearest goal: countdown, current phase, and the next checkpoint.
2. **Session player:** one item at a time, with play/pause track, record take, mark solid, and next. M1 shows the current section and focus for planned songs, and asks for a free, pressed, or cracked rating after a section take.
3. **Warmups:** ladders and standalone warmups, import a track from Files, pull to refresh from Trello.
4. **Songs:** repertoire by status. Detail shows key, notes, lyrics, and takes. M1 adds:
   - Plan section: goal, countdown, phase timeline, sections with ratings and takes, checkpoints.
   - Plan actions: Make a plan, Import plan, Export plan, Remove plan.
5. **Lessons:** package countdown and lesson notes.
6. **Settings:** practice plan, reminders, lessons, Trello, sample content. M2 adds an AI section.

## Later

- **Range history** across sessions, feeding key fitting (M2 starts this with RangeReading)
- **Native exercises:** pitch matching, range test, and interval drills; these replace web exercises
- **Lesson capture:** record, transcribe, and turn notes into tasks
- **Pre-lesson brief:** built from section ratings and the plan's teacher questions
- **Lyric memorization mode**
- **MyOps sync:** read and write song folders and `plan.json`
- **Siri shortcut:** "start practice"
- **Studio planner backend:** one key held server-side, with per-student limits (see PLAN_A_SONG.md)
- **Shared practice engine** with the magic trick app

## Success measures

- Practice days per week meet the target in 3 of 4 weeks.
- Every warmup ladder advances at least one rung per month.
- At least one song moves up a status each month.
- For a song with a goal: every high-difficulty section has a "free" take before the full-run phase starts.
