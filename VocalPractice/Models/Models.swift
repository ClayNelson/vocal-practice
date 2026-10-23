import Foundation
import SwiftData

@Model
final class Warmup {
    var id: UUID = UUID()
    var title: String = ""
    var ladderGroup: String?
    var ladderLevel: Int = 0
    var minutes: Int = 4
    /// File name inside the app's Documents/Warmups folder.
    var audioFileName: String?
    /// For warmups that live on YouTube instead of as an audio file (e.g. the Super Mario mashup).
    var linkURL: String?
    var isSolid: Bool = false
    var lastPracticed: Date?
    var source: String = ""
    var createdAt: Date = Date()
    /// Set when the warmup comes from (or was matched to) a Trello card; sync updates by this ID.
    var trelloCardID: String?
    /// The Trello attachment the current track was downloaded from, so unchanged tracks are not re-downloaded.
    var trelloAttachmentID: String?

    init(title: String, ladderGroup: String? = nil, ladderLevel: Int = 0, minutes: Int = 4,
         source: String = "", linkURL: String? = nil) {
        self.title = title
        self.ladderGroup = ladderGroup
        self.ladderLevel = ladderLevel
        self.minutes = minutes
        self.source = source
        self.linkURL = linkURL
    }

    var snapshot: WarmupSnapshot {
        WarmupSnapshot(id: id, title: title, ladderGroup: ladderGroup, ladderLevel: ladderLevel,
                       minutes: minutes, isSolid: isSolid, lastPracticed: lastPracticed)
    }
}

@Model
final class Song {
    var id: UUID = UUID()
    var title: String = ""
    var artist: String = ""
    var key: String = ""
    var statusRaw: String = SongStatus.learning.rawValue
    var minutes: Int = 5
    var lyrics: String = ""
    var notes: String = ""
    /// Path in the MyOps repo, e.g. songs/covers/good-ol-boys
    var myOpsPath: String = ""
    var showcase: Bool = false
    var lastPracticed: Date?
    var createdAt: Date = Date()

    /// The song's plan.json text, the source of truth. The fields below mirror it for display
    /// and queries; only PlanStore writes them.
    var planJSON: String?
    var goalType: String?
    var goalLabel: String?
    var goalDate: Date?
    var goalDateIsApprox: Bool = false
    var originalKey: String?
    var keyOptionsRaw: String = ""
    var rangeLowMidi: Int?
    var rangeHighMidi: Int?
    @Relationship(deleteRule: .cascade, inverse: \SongSection.song) var sections: [SongSection] = []
    @Relationship(deleteRule: .cascade, inverse: \Checkpoint.song) var checkpoints: [Checkpoint] = []

    var status: SongStatus {
        get { SongStatus(rawValue: statusRaw) ?? .learning }
        set { statusRaw = newValue.rawValue }
    }

    init(title: String, artist: String = "", status: SongStatus = .learning, myOpsPath: String = "") {
        self.title = title
        self.artist = artist
        self.statusRaw = status.rawValue
        self.myOpsPath = myOpsPath
    }

    var snapshot: SongSnapshot {
        SongSnapshot(id: id, title: title, status: status, minutes: minutes,
                     showcase: showcase, lastPracticed: lastPracticed)
    }
}

@Model
final class PracticeSession {
    var id: UUID = UUID()
    var date: Date = Date()
    var plannedMinutes: Int = 0
    var completedItemIDs: [UUID] = []
    var voiceCondition: Int = 3
    var notes: String = ""
    @Relationship(deleteRule: .cascade, inverse: \Take.session) var takes: [Take] = []

    init(date: Date = .now, plannedMinutes: Int, voiceCondition: Int) {
        self.date = date
        self.plannedMinutes = plannedMinutes
        self.voiceCondition = voiceCondition
    }
}

@Model
final class Take {
    var id: UUID = UUID()
    var itemID: UUID = UUID()
    var itemTitle: String = ""
    var audioFileName: String = ""
    var date: Date = Date()
    var session: PracticeSession?
    /// The plan section this take worked on, if any.
    var sectionID: String?
    /// free, pressed, or cracked
    var rating: String?

    init(itemID: UUID, itemTitle: String, audioFileName: String) {
        self.itemID = itemID
        self.itemTitle = itemTitle
        self.audioFileName = audioFileName
    }
}

/// A hard spot from a song's plan, with how it went last time.
@Model
final class SongSection {
    var id: UUID = UUID()
    /// The plan's section id, e.g. top-phrases.
    var sectionID: String = ""
    var title: String = ""
    var difficulty: String = Difficulty.medium.rawValue
    var focus: String = ""
    var order: Int = 0
    var lastPracticed: Date?
    /// free, pressed, or cracked
    var lastRating: String?
    var song: Song?

    init(sectionID: String, title: String, difficulty: String, focus: String, order: Int) {
        self.sectionID = sectionID
        self.title = title
        self.difficulty = difficulty
        self.focus = focus
        self.order = order
    }

    var snapshot: SectionSnapshot {
        SectionSnapshot(id: sectionID, title: title, focus: focus, difficulty: difficulty, order: order,
                        lastRating: lastRating, lastPracticed: lastPracticed)
    }
}

/// A dated decision from a song's plan, like "Lock key".
@Model
final class Checkpoint {
    var id: UUID = UUID()
    var title: String = ""
    var due: Date = Date()
    var done: Bool = false
    var song: Song?

    init(title: String, due: Date, done: Bool) {
        self.title = title
        self.due = due
        self.done = done
    }
}

@Model
final class Lesson {
    var id: UUID = UUID()
    var date: Date = Date()
    var number: Int = 0
    var notes: String = ""
    var isGifted: Bool = false

    init(date: Date, number: Int, notes: String = "", isGifted: Bool = false) {
        self.date = date
        self.number = number
        self.notes = notes
        self.isGifted = isGifted
    }
}
