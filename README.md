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

A welcome screen asks to connect Trello:

1. **Connect Trello.** Sign in to the Trello account the lesson board is shared with, and allow read access.
2. **Pick the board.** The app picks the lesson board, the Warmups list, and the lesson package card when it can; change any of them in Settings.
3. **Done.** It syncs once. Warmups and their tracks fill in, along with the lesson history.

"Skip for now" starts empty. To demo with Clay's content, use **Settings, Sample content**.

Then in **Settings**, set practice days and reminder time, and tap Save reminders.

## Trello sync

Pull-only: the app reads the board and never changes it.

| On the board | In the app |
| --- | --- |
| Each card in the Warmups list | A warmup. Title follows the card. "BFS to 200" style names become ladder rungs. |
| The card's uploaded audio file | The warmup's track, downloaded once and again only if the attachment changes |
| Package card lines like `4. 10/16`, plus "Gifted" lines | Lesson history; "30 Classes" sets the package size |

**When it syncs:**
- On launch, if the last sync was more than 6 hours ago
- When you pull to refresh on the Warmups tab
- When you tap **Sync now** in Settings

**What it leaves alone:**
- Solid flags, practice history, and takes are never touched.
- Nothing is deleted. A warmup whose card is archived stays until you remove it.
- Warmups added by hand keep their place. On first sync, a seeded warmup with a matching title is adopted, not duplicated.

Each person signs in with their own Trello account and gets a read-only token, stored in the iPhone Keychain. That's what lets Nicolette's students use their own boards.

### One-time setup (Clay)

1. **Create the API key.** Go to https://trello.com/apps/admin, create a Power-Up named "Vocal Practice" in your workspace, open its **Trello Auth** tab, and choose **Generate a new API key**. The key identifies the app, not a person. Do not use or share the secret.
2. **Add the repo secret** `TRELLO_API_KEY` with that key. Builds without it have sync turned off and show a warning in the Actions log.
3. **Choose a sign-in style:**
   - **Paste token (works now, no hosting):** do nothing more. Connect opens Trello in Safari; after tapping Allow, Trello shows a token to copy and paste back into the app.
   - **One tap (recommended before sharing):** host `web/trello-callback.html` on an https site you control (GitHub Pages, Vercel, or similar). Add that site's origin, for example `https://yourname.github.io`, under **Allowed origins** on the Power-Up's Trello Auth tab. Then set the repo **variable** (not secret) `TRELLO_RETURN_URL` to the full page URL. Sign-in then returns to the app automatically.
4. **Run the TestFlight workflow.**

## How a session is built

- Length follows the studio policy: 3 days a week = 60 min, 4 = 45, 5 = 30 (changeable on the Today screen).
- First half warmups. Ladders (Breath fire starter 125, 150, 175) schedule only the current rung: the lowest one not yet marked solid. Other warmups rotate, least recently practiced first.
- Second half songs in Learning, Polishing, or Performance ready: songs with an active plan first (nearest goal first), then showcase songs, then Learning, then least recently practiced. A planned song follows its current phase (see Song plans).
- A rough or tired voice check-in halves the song block and drops ladders one rung.

## Reviewing progress

- **Today** has a clock button that opens session history: date, voice condition, what got done, notes, and every take from that session.
- **Warmups** and **Songs** detail screens list the takes recorded for that item, newest first, so you can play an old take against a new one. Swipe to delete a take; the recording is removed too.
- **Lessons** shows practice days and the notes you saved since your last lesson, so they are ready when you sit down with Nicolette.

## Song plans

A plan works a song toward a dated goal, like a showcase. It has phases (listen, sections, full runs, maintenance, taper), the hard sections worth isolating, and dated checkpoints such as "Lock key". The format is `plan.json`, described in `docs/SONG_PLAN.md`.

- **Make a plan:** on a song's screen, tap **Make a plan**. Enter the goal date, key, range, and sections, plus any days off. The phases preview before you save. No network needed.
- **Import a plan:** tap the import button on the **Songs** tab and pick a `plan.json` from Files. It attaches to the song with the same title and artist, or creates the song. Importing over a plan replaces it but keeps section ratings that match by id.
- **Export a plan:** **Export plan** on the song's screen shares `<song>.plan.json`, with checkpoint done states included. Drop it back in the song's MyOps folder.
- **The plan-a-song skill:** Clay's Claude skill writes `plan.json` into `songs/covers/<song>/` in MyOps. Import that file to use it.

Once a plan is active:

- **Today** shows a goal card: countdown, current phase, and the next checkpoint (orange when overdue). Song rows show the mode: Listen, Section: Top phrases, Full run, or Taper run.
- **Section takes:** after a take on a section, the player asks how it felt (Free, Pressed, Cracked). The next session works the hardest unresolved section: cracked, then pressed, then never practiced, then the oldest.
- **Maintenance** phases schedule a full run on up to 3 days a week. **Taper** skips the song on a rough voice.

Validate a file on a Mac with `python3 tools/validate_plan.py path/to/plan.json`.

## Pitch screen

Tap the tuning fork on the Today screen. Sing and you get the note name, a sharp or flat meter, a scrolling pitch line over note lanes, and your range for the sitting (lowest and highest notes held for half a second). Use headphones if anything is playing, or the mic will hear the speaker.

The detector is YIN running on the live mic (`Pitch/PitchDetector.swift`), about 50 readings a second, with no network or account. It is the base for native exercises that will replace the Singing Carrots web step.

## Layout

```
VocalPractice/
  App/        app entry, tabs, settings keys
  Planner/    SessionPlanner and WeeklyProgress (pure Swift, unit tested)
  Models/     SwiftData models, PlanStore, sample seed data
  Plans/      SongPlan format, validator, offline planner (pure Swift, unit tested)
  Pitch/      YIN pitch detector, live mic tracker, pitch screen
  Trello/     sign-in, read-only client, pull sync, onboarding (mapping is pure Swift, unit tested)
  Services/   audio playback, take recording, reminders
  Views/      Today, session player, history, warmups, songs, lessons, settings
Tests/        planner, song plan, offline planner, pitch detector, and Trello mapping tests
docs/SPEC.md  v1 spec and v2 candidates
docs/SONG_PLAN.md  plan.json format shared by the plan-a-song skill and the app
docs/IMPLEMENTATION_PLAN.md  next build (M0 CI, M1 song plans, M2 Claude), for Claude Code
tools/        validate_plan.py for plan.json files
web/          Trello sign-in relay page (host it for one-tap sign-in)
```

## Not yet built (v2)

Range history across sessions, native pitch exercises, lesson recording and transcription, pre-lesson brief, showcase countdown, key fitting, lyric memorization, MyOps sync, Siri shortcut.
