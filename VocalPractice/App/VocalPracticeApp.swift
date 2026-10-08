import SwiftData
import SwiftUI

@main
struct VocalPracticeApp: App {
    let container: ModelContainer = {
        let schema = Schema([Warmup.self, Song.self, PracticeSession.self, Take.self, Lesson.self])
        let container = try! ModelContainer(for: schema)
        SeedData.seedIfEmpty(container.mainContext)
        return container
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TodayView().tabItem { Label("Today", systemImage: "music.mic") }
            WarmupsView().tabItem { Label("Warmups", systemImage: "waveform") }
            SongsView().tabItem { Label("Songs", systemImage: "music.note.list") }
            LessonsView().tabItem { Label("Lessons", systemImage: "graduationcap") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.indigo)
    }
}

/// Shared settings keys (studio policy defaults: 4 days x 45 minutes, 30-lesson package).
enum Prefs {
    static let daysPerWeek = "daysPerWeek"
    static let reminderHour = "reminderHour"
    static let reminderMinute = "reminderMinute"
    static let reminderDays = "reminderDays"
    static let packageSize = "packageSize"
}
