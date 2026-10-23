import Foundation
import SwiftData

/// First-launch content from Nicolette's Trello board, her Aug 14 email, and MyOps.
/// Audio files are not bundled; import each m4a from the Warmups screen.
enum SeedData {
    static func seedIfEmpty(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Warmup>())) ?? 0
        guard count == 0 else { return }

        let trello = "Trello: Clays Vocal Lessons"
        let warmups: [Warmup] = [
            Warmup(title: "Precursor to breath fire starters", ladderGroup: "Breath fire starter", ladderLevel: 0, minutes: 3, source: trello),
            Warmup(title: "Breath fire starter to 125", ladderGroup: "Breath fire starter", ladderLevel: 125, minutes: 4, source: trello),
            Warmup(title: "Breath fire starter to 150", ladderGroup: "Breath fire starter", ladderLevel: 150, minutes: 4, source: trello),
            Warmup(title: "BFS to 175", ladderGroup: "Breath fire starter", ladderLevel: 175, minutes: 4, source: trello),
            Warmup(title: "Breath fire starter to F consonant", minutes: 4, source: "Email from Nicolette, Aug 14 2026"),
            Warmup(title: "Somewhere Over the Rainbow octave jumps", minutes: 4, source: trello),
            Warmup(title: "Waltz of the Flowers", minutes: 4, source: trello),
            Warmup(title: "Vegas Road Rage", minutes: 4, source: trello),
            Warmup(title: "Super Mario x Inspector Gadget mashup", minutes: 3, source: trello),
        ]
        warmups.forEach { context.insert($0) }

        let songs: [Song] = [
            Song(title: "Good Ol' Boys", artist: "Waylon Jennings", myOpsPath: "songs/covers"),
            Song(title: "There Ain't No Good Chain Gang", artist: "Johnny Cash & Waylon Jennings", myOpsPath: "songs/covers"),
            Song(title: "Cadillac's Daughter", artist: "Clay Nelson", status: .seam),
        ]
        let prettyWoman = Song(title: "Oh, Pretty Woman", artist: "Roy Orbison",
                               myOpsPath: "songs/covers/oh-pretty-woman-roy-orbison")
        prettyWoman.key = "A"
        prettyWoman.minutes = 6
        prettyWoman.showcase = true
        prettyWoman.notes = "Showcase, late Jan 2027. Lock key (A, Ab, or G) by Nov 8. See docs/examples/showcase-oh-pretty-woman.md"
        songs.forEach { context.insert($0) }
        context.insert(prettyWoman)

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
}
