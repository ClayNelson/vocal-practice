# Vocal Practice: V1 Spec

Owner: Clay Nelson
Status: Draft, October 7, 2026

## Problem

Clay takes weekly lessons with Nicolette Holman (Mesmerize Studio). Her warmups arrive as audio tracks on a Trello board and by email, and his songs live in MyOps. Practice happens, but nothing queues it, tracks it, or shows progress. The studio policy asks for 3 to 5 practice days a week, split half warmups and half songs. V1 makes that routine automatic.

## Goals

1. Open the app, tap Start, and get today's session already built.
2. Hit the weekly practice target Nicolette sets (3 to 5 days).
3. Know where every song stands and what to work on next.
4. Hear improvement over time.

## Non-goals for v1

- Pitch detection and range analysis (v2)
- Lesson recording and transcription (v2)
- Sync with MyOps (v2). Trello sync shipped in v1.1, see below.
- Sharing, accounts, backend, App Store release

## Source material

| Source | What it gives the app |
| --- | --- |
| Trello board "Clays Vocal Lessons", Warmups list | Warmup tracks (m4a): Precursor to breath fire starters; Breath fire starter to 125, 150, 175; Somewhere Over the Rainbow octave jumps; Waltz of the Flowers; Vegas Road Rage; Super Mario x Inspector Gadget mashup |
| Email from Nicolette, Aug 14 2026 | Breath fire starter to F consonant (m4a) |
| Trello "2026 Mesmerize Studio Policies" card | Practice rules: 3 days x 60 min, 4 x 45, or 5 x 30; half warmups, half songs |
| Trello "1st Class Package" card | 30-lesson package; lessons on 8/19, 8/26, 9/3 so far; one gifted lesson used 9/11 |
| MyOps `/songs/covers/` | Song repertoire (Good Ol' Boys, There Ain't No Good Chain Gang, originals) |

## Core loop

1. **Remind.** A notification on each scheduled practice day at a chosen time.
2. **Plan.** The session planner fills the chosen length (30, 45, or 60 min): first half warmups, second half songs.
3. **Practice.** The player runs each item in order: plays Nicolette's track for warmups, shows key and notes for songs, and records a take of each.
4. **Log.** End of session: rate voice condition (1 to 5), mark items solid, add a note.
5. **Review.** Weekly progress against target; per-item take history to compare old and new.

## Session planner rules

- Length = user choice of 30, 45, or 60 minutes (default from weekly plan: 3 days uses 60, 4 uses 45, 5 uses 30).
- Warmup half:
  - Ladder warmups (Breath fire starter 125 to 150 to 175) contribute only the current rung: the lowest level not yet marked solid. Precursor comes first until marked solid.
  - Standalone warmups rotate by least recently practiced.
  - Fill until the warmup half is used; never split an item.
- Song half:
  - Eligible statuses: learning, polishing, performance ready (seams and retired songs excluded).
  - Order: songs flagged for an upcoming showcase first, then learning, then least recently practiced.
- Voice condition 1 or 2 at check-in: halve the song block and drop the highest ladder rung.
- Web exercises count toward the warmup half and rotate by least recently practiced, same as standalone warmups.

## Exercise sources

Every warmup item has a source type, so the queue never depends on where an exercise lives. Swapping one source for another touches a single component, not the planner or the player flow.

| Source type | What the player does | V1 |
| --- | --- | --- |
| Track | Plays Nicolette's audio file and records a take (current behavior) | Yes |
| Web | Opens a saved Singing Carrots exercise in an in-app web view; on close, logs the session and asks "mark solid?" | Yes |
| Native | Built-in pitch exercise using the app's own pitch detector (see V2) | No |

Web source details:

- Each web exercise stores a title, a URL on singingcarrots.com, and estimated minutes. Clay adds them by pasting a link.
- Rendered in a `WKWebView` wrapped as a SwiftUI view (`WebExerciseView`).
- Microphone: `NSMicrophoneUsageDescription` in Info.plist, plus a `WKUIDelegate` that grants media capture for the singingcarrots.com origin only, so the exercises work without a prompt every session.
- Login: default persistent `WKWebsiteDataStore`, so the Singing Carrots session survives app restarts.
- Scores are not read back from the page in v1. Completion is logged when the view closes; Clay can type a result into the session note.
- Navigation outside singingcarrots.com opens in Safari rather than in the app.
- Distribution: personal builds and TestFlight for a few friends only (each friend uses their own Singing Carrots login). If the app ever goes to the App Store, remove the web source or replace it with native exercises.

## Data model

| Entity | Fields |
| --- | --- |
| Warmup | title, source type (track, web, native), ladder group, ladder level, est. minutes, audio file (track), URL (web), solid flag, last practiced |
| Song | title, artist, key, status, est. minutes, lyrics, notes, MyOps path, showcase flag, last practiced |
| Session | date, planned minutes, completed item ids, voice condition, notes |
| Take | session, item, audio file, date |
| Lesson | date, lesson number, notes |
| Settings | days per week, reminder time, reminder weekdays, package size |

Song status pipeline: seam, learning, polishing, performance ready, recorded, retired.

## Screens

1. **Today**: weekly ring (days practiced vs target), Start button with today's planned session, next lesson.
2. **Session player**: one item at a time, play/pause track, record take, mark solid, next. Web items open the web view full screen with a Done button that returns to the queue.
3. **Warmups**: library, import m4a from Files, add a Singing Carrots link, ladder view showing current rung.
4. **Songs**: repertoire by status, detail with key, lyrics, notes, takes.
5. **Lessons**: package countdown (used / 30), lesson notes.
6. **Settings**: days per week, reminder time and days.

## V1.1: Trello sync and multi-user sign-in

Added October 23, 2026 so Nicolette can hand the app (via TestFlight) to her students.

- Each person signs in with their own Trello account through Trello's authorize page (read scope, no expiry). The token lives in the Keychain; the app's API key is set at build time from the `TRELLO_API_KEY` secret.
- Sign-in returns through a hosted relay page (`web/trello-callback.html`, set with `TRELLO_RETURN_URL`) or, without one, by pasting the token Trello shows.
- Onboarding picks the lesson board, the Warmups list, and the lesson package card; all three are changeable in Settings.
- Pull-only sync: cards become warmups (ladder rungs parsed from names), audio attachments become tracks, package card lines become lessons. Nothing is written to Trello and nothing local is deleted.
- Clay's seed content no longer loads automatically; it is under Settings, Sample content.
- Details and setup: README, Trello sync.

## Plan a song (decided, not built)

In-app song planning: offline planner first (free, doubles as showcase mode), AI research on top with an Anthropic key entered in Settings, provider pluggable for a studio backend later. See [PLAN_A_SONG.md](PLAN_A_SONG.md).

## V2 candidates

Worked example that prioritizes these: [Oh, Pretty Woman to the January showcase](examples/showcase-oh-pretty-woman.md).

- Pitch tracking and weekly range (highest and lowest clean note)
- Native exercise source: own pitch matching, range test, and interval drills built on the pitch tracker, as a replacement for web exercises
- Lesson capture: record, transcribe, turn notes into tasks
- Pre-lesson brief
- Showcase countdown that reweights the queue
- Key fitting and transposition
- Lyric memorization mode
- MyOps sync; Siri shortcut "start practice"
- Share the practice engine with the magic trick app

## Success measures

- Practice days per week meets target in 3 of 4 weeks
- Every warmup ladder advances at least one rung per month
- At least one song moves up a status each month
