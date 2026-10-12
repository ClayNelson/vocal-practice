import Foundation
import SwiftData

/// First-launch content from Nicolette's Trello board, her Aug 14 email, and MyOps.
/// Her warmup recordings ship in the bundle (Resources/Warmups) and are copied into the
/// app's Warmups folder on launch, so every warmup has its track without a Files import.
enum SeedData {
    /// Bundled m4a resource names keyed by warmup title.
    static let bundledTracks: [String: String] = [
        "Precursor to breath fire starters": "vp-precursor-to-breath-fire-starters",
        "Breath fire starter to 125": "vp-breath-fire-starter-to-125",
        "Breath fire starter to 150": "vp-breath-fire-starter-to-150",
        "BFS to 175": "vp-bfs-to-175",
        "Breath fire starter to F consonant": "vp-breath-fire-starter-to-f-consonant",
        "Somewhere Over the Rainbow octave jumps": "vp-somewhere-over-the-rainbow-octave-jumps",
        "Waltz of the Flowers": "vp-waltz-of-the-flowers",
        "Vegas Road Rage": "vp-vegas-road-rage",
    ]

    /// Warmups that are a video link rather than a recording.
    static let bundledLinks: [String: String] = [
        "Super Mario x Inspector Gadget mashup": "https://youtube.com/watch?v=35ge5wu-EB0",
    ]

    static func seedIfEmpty(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Warmup>())) ?? 0
        if count == 0 { insertStarterContent(context) }
        attachBundledTracks(context)
    }

    private static func insertStarterContent(_ context: ModelContext) {
        let trello = "Trello: Clays Vocal Lessons"
        let warmups: [Warmup] = [
            Warmup(title: "Precursor to breath fire starters", ladderGroup: "Breath fire starter", ladderLevel: 0, minutes: 3, source: trello),
            Warmup(title: "Breath fire starter to 125", ladderGroup: "Breath fire starter", ladderLevel: 125, minutes: 4, source: trello),
            Warmup(title: "Breath fire starter to 150", ladderGroup: "Breath fire starter", ladderLevel: 150, minutes: 4, source: trello),
            Warmup(title: "BFS to 175", ladderGroup: "Breath fire starter", ladderLevel: 175, minutes: 4, source: trello),
            Warmup(title: "Breath fire starter to F consonant", minutes: 4, source: "Email from Nicolette, Aug 14 2026"),
            Warmup(title: "Somewhere Over the Rainbow octave jumps", minutes: 4, source: trello),
            Warmup(title: "Waltz of the Flowers", minutes: 7, source: trello),
            Warmup(title: "Vegas Road Rage", minutes: 4, source: trello),
            Warmup(title: "Super Mario x Inspector Gadget mashup", minutes: 3, source: trello),
        ]
        warmups.forEach { context.insert($0) }

        let songs: [Song] = [
            Song(title: "Good Ol' Boys", artist: "Waylon Jennings", myOpsPath: "songs/covers"),
            Song(title: "There Ain't No Good Chain Gang", artist: "Johnny Cash & Waylon Jennings", myOpsPath: "songs/covers"),
            Song(title: "Cadillac's Daughter", artist: "Clay Nelson", status: .seam),
        ]
        songs.forEach { context.insert($0) }

        let lessons: [(String, Int, Bool)] = [("2026-08-19", 1, false), ("2026-08-26", 2, false),
                                              ("2026-09-03", 3, false), ("2026-09-11", 0, true)]
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        for (day, number, gifted) in lessons {
            if let date = fmt.date(from: day) {
                context.insert(Lesson(date: date, number: number,
                                      notes: gifted ? "Gifted lesson used to cover same-day cancel" : "",
                                      isGifted: gifted))
            }
        }
        try? context.save()
    }

    /// Copies bundled recordings into the Warmups folder for any warmup still missing audio,
    /// and fills in video links. Runs every launch so existing installs pick up new bundles.
    static func attachBundledTracks(_ context: ModelContext) {
        guard let warmups = try? context.fetch(FetchDescriptor<Warmup>()) else { return }
        var changed = false
        for warmup in warmups {
            if warmup.audioFileName == nil,
               let resource = bundledTracks[warmup.title],
               let source = Bundle.main.url(forResource: resource, withExtension: "m4a") {
                let name = "\(resource).m4a"
                let dest = AudioStorage.warmups.appending(path: name)
                if FileManager.default.fileExists(atPath: dest.path)
                    || (try? FileManager.default.copyItem(at: source, to: dest)) != nil {
                    warmup.audioFileName = name
                    changed = true
                }
            }
            if warmup.linkURL == nil, let link = bundledLinks[warmup.title] {
                warmup.linkURL = link
                changed = true
            }
        }
        if changed { try? context.save() }
    }
}
