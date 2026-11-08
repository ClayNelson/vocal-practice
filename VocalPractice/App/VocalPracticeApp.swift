import SwiftData
import SwiftUI

@main
struct VocalPracticeApp: App {
    let container: ModelContainer = {
        let schema = Schema([Warmup.self, Song.self, SongSection.self, Checkpoint.self,
                             PracticeSession.self, Take.self, Lesson.self])
        // No automatic seed: students start empty and fill from Trello during onboarding.
        // Clay's starter set is available from Settings > Sample content.
        return try! ModelContainer(for: schema)
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        .backgroundTask(.appRefresh(BoardRefresh.taskID)) { [container] in
            await BoardRefresh.run(container: container)
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Prefs.onboarded) private var onboarded = false
    @AppStorage(Prefs.trelloChanges) private var changesData = Data()
    @AppStorage(Prefs.trelloChangesSeen) private var changesSeen: Double = 0

    private var unseenCount: Int {
        (changesData.decoded([BoardMapping.Change].self) ?? []).filter { $0.date.timeIntervalSince1970 > changesSeen }.count
    }

    var body: some View {
        TabView {
            TodayView().tabItem { Label("Today", systemImage: "music.mic") }
                .badge(unseenCount)
            WarmupsView().tabItem { Label("Warmups", systemImage: "waveform") }
            SongsView().tabItem { Label("Songs", systemImage: "music.note.list") }
            LessonsView().tabItem { Label("Lessons", systemImage: "graduationcap") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.indigo)
        .sheet(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
            OnboardingView { onboarded = true }
        }
        // Pull new warmups and lessons when the app comes forward, at most every few hours.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .background { BoardRefresh.schedule() }
            guard phase == .active, onboarded else { return }
            Task { await TrelloSync.syncIfStale(context: context) }
        }
    }
}

/// Shared settings keys (studio policy defaults: 4 days x 45 minutes, 30-lesson package).
enum Prefs {
    static let daysPerWeek = "daysPerWeek"
    static let reminderHour = "reminderHour"
    static let reminderMinute = "reminderMinute"
    static let reminderDays = "reminderDays"
    static let packageSize = "packageSize"
    static let onboarded = "onboarded"
    static let trelloMember = "trelloMember"
    static let trelloBoardID = "trelloBoardID"
    static let trelloBoardName = "trelloBoardName"
    static let trelloListID = "trelloListID"
    static let trelloPackageCardID = "trelloPackageCardID"
    static let trelloLastSync = "trelloLastSync"
    static let trelloMemberID = "trelloMemberID"
    static let trelloActivitySince = "trelloActivitySince"
    static let trelloRoutines = "trelloRoutines"
    static let trelloChanges = "trelloChanges"
    static let trelloChangesSeen = "trelloChangesSeen"
    /// The routine chosen on Today; empty means pick by session length.
    static let routineChoice = "routineChoice"
    static let boardNotifications = "boardNotifications"
}
