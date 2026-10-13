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

## TestFlight

Builds go to TestFlight from GitHub Actions on a Mac runner, so no Mac is needed to ship a build. Run it from the Actions tab or the GitHub mobile app: **Actions, TestFlight, Run workflow**. Each run tests, archives, signs, and uploads; the build number is the run number.

One-time setup:

1. **App Store Connect, Apps, +, New App.** Platform iOS, bundle ID `app.haklo.vocalpractice` (register it under Certificates, Identifiers & Profiles first if it isn't in the list). App names are unique across the store, so use something like "Vocal Practice Clay"; the home-screen name stays "Vocal Practice".
2. **Users and Access, Integrations, App Store Connect API, +.** Role **Admin** (needed for cloud-managed signing). Download the .p8 once and note the Key ID and Issuer ID.
3. **Repo secrets** (Settings, Secrets and variables, Actions):
   - `APPLE_TEAM_ID`: 10-character team ID from developer.apple.com, Membership
   - `ASC_KEY_ID`: the API key's ID
   - `ASC_ISSUER_ID`: the issuer ID above the key list
   - `ASC_KEY_P8`: the full text of the .p8 file, including the BEGIN and END lines
4. **TestFlight tab:** add yourself as an internal tester. For friends, create an external group and add their emails; the first external build gets a short Apple beta review.

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

## Pitch screen

Tap the tuning fork on the Today screen. Sing and you get the note name, a sharp or flat meter, a scrolling pitch line over note lanes, and your range for the sitting (lowest and highest notes held for half a second). Use headphones if anything is playing, or the mic will hear the speaker.

The detector is YIN running on the live mic (`Pitch/PitchDetector.swift`), about 50 readings a second, with no network or account. It is the base for native exercises that will replace the Singing Carrots web step.

## Layout

```
VocalPractice/
  App/        app entry, tabs, settings keys
  Planner/    SessionPlanner and WeeklyProgress (pure Swift, unit tested)
  Models/     SwiftData models and first-launch seed data
  Pitch/      YIN pitch detector, live mic tracker, pitch screen
  Services/   audio playback, take recording, reminders
  Views/      Today, session player, warmups, songs, lessons, settings
Tests/        planner and pitch detector tests
docs/SPEC.md  v1 spec and v2 candidates
```

## Not yet built (v2)

Range history across sessions, native pitch exercises, lesson recording and transcription, pre-lesson brief, showcase countdown, key fitting, lyric memorization, MyOps and Trello sync, Siri shortcut.
