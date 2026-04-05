import Foundation
import UserNotifications

/// Manages local notifications for feeding reminders.
/// Thread-safe singleton; all UNUserNotificationCenter calls run on the main actor.
@MainActor
final class NotificationManager: NSObject, Sendable {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    // MARK: - UserDefaults Keys

    private let enabledKey = "feedingReminderEnabled"
    private let intervalKey = "feedingReminderInterval" // in minutes

    /// Whether feeding reminders are enabled
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if !newValue { cancelFeedingReminder() }
        }
    }

    /// Reminder interval in minutes (default 180 = 3 hours)
    var intervalMinutes: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: intervalKey)
            return val > 0 ? val : 180
        }
        set {
            UserDefaults.standard.set(newValue, forKey: intervalKey)
        }
    }

    // MARK: - Predefined Intervals

    struct ReminderInterval: Identifiable {
        let id: Int  // minutes
        let label: String

        static let options: [ReminderInterval] = [
            .init(id: 90,  label: "1.5 hours"),
            .init(id: 120, label: "2 hours"),
            .init(id: 150, label: "2.5 hours"),
            .init(id: 180, label: "3 hours"),
            .init(id: 240, label: "4 hours"),
        ]
    }

    // MARK: - Permission

    /// Request notification permission. Returns true if granted.
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            return false
        }
    }

    /// Check current authorization status
    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Schedule Feeding Reminder

    private let feedingReminderID = "com.babylove.feedingReminder"

    /// Schedule a feeding reminder `intervalMinutes` after the given feeding time.
    /// Cancels any existing feeding reminder first.
    func scheduleFeedingReminder(afterFeedingAt feedTime: Date = Date()) {
        guard isEnabled else { return }

        // Cancel previous
        center.removePendingNotificationRequests(withIdentifiers: [feedingReminderID])

        let fireDate = feedTime.addingTimeInterval(Double(intervalMinutes) * 60)

        // Don't schedule if fire date is in the past
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to Feed"
        content.body = "It's been \(formattedInterval()) since the last feeding."
        content.sound = .default
        content.categoryIdentifier = "FEEDING_REMINDER"

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let request = UNNotificationRequest(
            identifier: feedingReminderID,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("BabyLove: Failed to schedule feeding reminder: \(error)")
            }
        }
    }

    /// Cancel any pending feeding reminder
    func cancelFeedingReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [feedingReminderID])
    }

    // MARK: - Helpers

    private func formattedInterval() -> String {
        let hours = intervalMinutes / 60
        let mins = intervalMinutes % 60
        if mins == 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        return "\(hours)h \(mins)m"
    }
}
