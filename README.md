# Vocal Practice

A personal iOS app that turns Nicolette's lessons into a daily practice routine: it builds each session (half warmups, half songs), reminds you on practice days, plays her warmup tracks, records a take of everything, and tracks songs and lessons.

See [docs/SPEC.md](docs/SPEC.md) for the full spec.

## Run it

Requirements: a Mac with Xcode 15 or later, iOS 17 device or simulator.

```sh
brew install xcodegen
git clone https://github.com/ClayNelson/vocal-practice
cd vocal-practice
xcodegen generate
open VocalPractice.xcodeproj
```

In Xcode, pick your Team under Signing & Capabilities for the VocalPractice target, choose your iPhone, and press Run. Run the planner tests with Cmd+U.

`xcodegen generate` writes `VocalPractice.xcodeproj` and `VocalPractice/Info.plist`; both are generated and ignored by git. Re-run it after adding or removing source files.

## First launch

The app seeds itself with Nicolette's warmups (from the Trello board and her Aug 14 email), your current covers, and your lesson history. Her eight warmup recordings ship inside the app (`VocalPractice/Resources/Warmups`) and are attached to the matching warmups on launch, so nothing needs importing. The Super Mario x Inspector Gadget mashup is a YouTube video on Trello, not a recording; the app links to it instead.

1. In **Settings**, set practice days and reminder time, then tap Save reminders.
2. To add a new warmup Nicolette sends later, tap + on the **Warmups** tab, then open it and tap Import track from Files. Or drop the m4a into `Resources/Warmups` and add it to `SeedData.bundledTracks` so every install gets it.

## How a session is built

- Length follows the studio policy: 3 days a week = 60 min, 4 = 45, 5 = 30 (changeable on the Today screen).
- First half warmups. Ladders (Breath fire starter 125, 150, 175) schedule only the current rung: the lowest one not yet marked solid. Other warmups rotate, least recently practiced first.
- Second half songs in Learning, Polishing, or Performance ready: showcase songs first, then Learning, then least recently practiced.
- A rough or tired voice check-in halves the song block and drops ladders one rung.

## Reviewing progress

- **Today** has a clock button that opens session history: date, voice condition, what got done, notes, and every take from that session.
- **Warmups** and **Songs** detail screens list the takes recorded for that item, newest first, so you can play an old take against a new one. Swipe to delete a take; the recording is removed too.
- **Lessons** shows practice days and the notes you saved since your last lesson, so they are ready when you sit down with Nicolette.

## Layout

```
VocalPractice/
  App/        app entry, tabs, settings keys
  Planner/    SessionPlanner and WeeklyProgress (pure Swift, unit tested)
  Models/     SwiftData models and first-launch seed data
  Resources/  Nicolette's warmup recordings (bundled m4a)
  Services/   audio playback, take recording, reminders
  Views/      Today, session player, history, warmups, songs, lessons, settings
Tests/        planner tests
docs/SPEC.md  v1 spec and v2 candidates
```

## Not yet built (v2)

Pitch and range tracking, lesson recording and transcription, pre-lesson brief, showcase countdown, key fitting, lyric memorization, MyOps and Trello sync, Siri shortcut.
