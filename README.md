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

## First launch

The app seeds itself with Nicolette's warmups (from the Trello board and her Aug 14 email), your current covers, and your lesson history. Audio tracks are not bundled:

1. Save the m4a files from Trello and email to Files on your iPhone.
2. On the **Warmups** tab, tap the download icon next to each warmup and pick its track.
3. In **Settings**, set practice days and reminder time, then tap Save reminders.

## How a session is built

- Length follows the studio policy: 3 days a week = 60 min, 4 = 45, 5 = 30 (changeable on the Today screen).
- First half warmups. Ladders (Breath fire starter 125, 150, 175) schedule only the current rung: the lowest one not yet marked solid. Other warmups rotate, least recently practiced first.
- Second half songs in Learning, Polishing, or Performance ready: showcase songs first, then Learning, then least recently practiced.
- A rough or tired voice check-in halves the song block and drops ladders one rung.

## Layout

```
VocalPractice/
  App/        app entry, tabs, settings keys
  Planner/    SessionPlanner and WeeklyProgress (pure Swift, unit tested)
  Models/     SwiftData models and first-launch seed data
  Services/   audio playback, take recording, reminders
  Views/      Today, session player, warmups, songs, lessons, settings
Tests/        planner tests
docs/SPEC.md  v1 spec and v2 candidates
```

## Not yet built (v2)

Pitch and range tracking, lesson recording and transcription, pre-lesson brief, showcase countdown, key fitting, lyric memorization, MyOps and Trello sync, Siri shortcut.
