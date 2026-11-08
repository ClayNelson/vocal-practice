import BackgroundTasks
import SwiftData
import UserNotifications

/// Checks the lesson board in the background and notifies when the teacher changed something.
/// iOS decides when background refresh runs (usually a few times a day), so this is "within hours", not instant.
enum BoardRefresh {
    static let taskID = "app.haklo.vocalpractice.board-refresh"

    /// Asks iOS for the next check, no sooner than three hours from now.
    static func schedule() {
        guard TrelloSync.isConnected else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = .now.addingTimeInterval(3 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func run(container: ModelContainer) async {
        schedule()
        guard TrelloSync.isConnected,
              let report = try? await TrelloSync.run(context: container.mainContext),
              !report.newChanges.isEmpty else { return }
        await notify(report.newChanges)
    }

    /// Turns on board notifications, asking for permission the first time. Returns whether they're allowed.
    static func enableNotifications() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { schedule() }
        return granted
    }

    private static func notify(_ changes: [BoardMapping.Change]) async {
        guard UserDefaults.standard.bool(forKey: Prefs.boardNotifications) else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized,
              let first = changes.first else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(first.who) updated your lesson board"
        content.body = changes.count == 1 ? first.text : "\(first.text), and \(changes.count - 1) more"
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "board-changes", content: content, trigger: nil))
    }
}
