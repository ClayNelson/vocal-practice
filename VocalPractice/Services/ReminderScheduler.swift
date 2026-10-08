import Foundation
import UserNotifications

/// Weekly repeating practice reminders on chosen weekdays.
enum ReminderScheduler {
    static let idPrefix = "practice-reminder-"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// - Parameters:
    ///   - weekdays: Calendar weekday numbers (1 = Sunday ... 7 = Saturday).
    ///   - hour/minute: local time.
    static func schedule(weekdays: Set<Int>, hour: Int, minute: Int, minutes: Int) async {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing)

        for day in weekdays {
            let content = UNMutableNotificationContent()
            content.title = "Time to sing"
            content.body = "Your \(minutes)-minute session is ready: half warmups, half songs."
            content.sound = .default
            var components = DateComponents()
            components.weekday = day
            components.hour = hour
            components.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: "\(idPrefix)\(day)", content: content, trigger: trigger))
        }
    }
}
