import Foundation

/// Plans that ship with the app. Pretty Woman is the hand-built reference plan from MyOps
/// (songs/covers/oh-pretty-woman-roy-orbison/plan.json), used by Sample content and the tests.
enum SamplePlans {
    static let prettyWomanJSON = """
    {
      "schemaVersion": 1,
      "song": {
        "title": "Oh, Pretty Woman",
        "artist": "Roy Orbison",
        "reference": "A Black and White Night (live, 1988)",
        "originalKey": "A",
        "keyOptions": ["A", "Ab", "G"],
        "range": { "low": "E3", "high": "F#4" },
        "tempoBPM": 104,
        "minutesPerPass": 6
      },
      "goal": {
        "type": "showcase",
        "label": "Vocal showcase",
        "date": "2027-01-25",
        "dateIsApprox": true
      },
      "sections": [
        { "id": "top-phrases", "title": "Top phrases", "difficulty": "high", "focus": "Sustained belts near F#4; free, not loud. Half volume first." },
        { "id": "mercy-growl", "title": "Mercy and growl", "difficulty": "medium", "focus": "Staged character beats: commit to the timing, safe growl technique." },
        { "id": "bridge-climb", "title": "Bridge climb", "difficulty": "high", "focus": "Breath points through the pursuit; the climb into the top without pressing." },
        { "id": "the-turn", "title": "The turn and outro", "difficulty": "medium", "focus": "Real deflation before the reversal, then let the payoff land." }
      ],
      "phases": [
        { "id": "absorb", "title": "Absorb and key", "start": "2026-10-26", "end": "2026-11-08", "songBlock": "listen", "focusSections": [], "notes": "Daily listening to the reference. Map breath points. Speak in rhythm over the riff. Test A, Ab, G." },
        { "id": "build-top", "title": "Build the top", "start": "2026-11-09", "end": "2026-11-29", "songBlock": "sections", "focusSections": ["top-phrases", "bridge-climb"], "notes": "Half volume, then build. Thanksgiving week is maintenance only." },
        { "id": "character", "title": "Character and story", "start": "2026-11-30", "end": "2026-12-20", "songBlock": "sections", "focusSections": ["mercy-growl", "the-turn", "top-phrases"], "notes": "Growl technique with Nicolette first. First full recorded takes in LUNA." },
        { "id": "holiday", "title": "Holiday maintenance", "start": "2026-12-21", "end": "2027-01-03", "songBlock": "maintenance", "focusSections": [], "notes": "Two or three full runs a week. No new changes." },
        { "id": "performance", "title": "Performance mode", "start": "2027-01-04", "end": "2027-01-17", "songBlock": "fullRun", "focusSections": [], "notes": "Standing, start to finish, no stopping. TikTok Live dress rehearsal." },
        { "id": "taper", "title": "Taper", "start": "2027-01-18", "end": "2027-01-25", "songBlock": "taper", "focusSections": [], "notes": "Short runs, nothing new, rest the day before." }
      ],
      "checkpoints": [
        { "title": "Lock key (A, Ab, or G)", "due": "2026-11-08", "done": false },
        { "title": "Lock backing track and arrangement", "due": "2026-12-20", "done": false },
        { "title": "Confirm showcase date", "due": "2026-11-15", "done": false }
      ],
      "questionsForTeacher": [
        "Is A the right key for me, or should I go down?",
        "How do I sustain the repeated top belts without pressing?",
        "What's a safe growl technique that holds up across repeated runs?",
        "Which warmups should I aim at this song?"
      ],
      "myOpsPath": "songs/covers/oh-pretty-woman-roy-orbison",
      "generatedBy": "plan-a-song skill (hand-built first example)",
      "generatedAt": "2026-10-23"
    }
    """

    static var prettyWoman: SongPlan { try! SongPlan.decode(Data(prettyWomanJSON.utf8)) }
}
