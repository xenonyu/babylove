import Foundation
import UserNotifications

/// Manages local notifications for feeding reminders.
/// Thread-safe singleton; all UNUserNotificationCenter calls run on the main actor.
@MainActor
final class NotificationManager: NSObject, Sendable {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    // MARK: - Feeding Reminder UserDefaults Keys

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

    /// Feeding reminder interval in minutes (default 180 = 3 hours)
    var intervalMinutes: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: intervalKey)
            return val > 0 ? val : 180
        }
        set {
            UserDefaults.standard.set(newValue, forKey: intervalKey)
        }
    }

    // MARK: - Diaper Reminder UserDefaults Keys

    private let diaperEnabledKey = "diaperReminderEnabled"
    private let diaperIntervalKey = "diaperReminderInterval" // in minutes

    /// Whether diaper reminders are enabled
    var isDiaperEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: diaperEnabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: diaperEnabledKey)
            if !newValue { cancelDiaperReminder() }
        }
    }

    /// Diaper reminder interval in minutes (default 120 = 2 hours)
    var diaperIntervalMinutes: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: diaperIntervalKey)
            return val > 0 ? val : 120
        }
        set {
            UserDefaults.standard.set(newValue, forKey: diaperIntervalKey)
        }
    }

    // MARK: - Predefined Intervals

    struct ReminderInterval: Identifiable {
        let id: Int  // minutes
        let labelKey: String

        var label: String {
            NSLocalizedString(labelKey, comment: "")
        }

        static let options: [ReminderInterval] = [
            .init(id: 90,  labelKey: "notification.interval.1_5h"),
            .init(id: 120, labelKey: "notification.interval.2h"),
            .init(id: 150, labelKey: "notification.interval.2_5h"),
            .init(id: 180, labelKey: "notification.interval.3h"),
            .init(id: 240, labelKey: "notification.interval.4h"),
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
        content.title = NSLocalizedString("notification.feedingTitle", comment: "")
        content.body = String(format: NSLocalizedString("notification.feedingBody %@", comment: ""), formattedInterval(intervalMinutes))
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

    // MARK: - Schedule Diaper Reminder

    private let diaperReminderID = "com.babylove.diaperReminder"

    /// Schedule a diaper reminder `diaperIntervalMinutes` after the given change time.
    /// Cancels any existing diaper reminder first.
    func scheduleDiaperReminder(afterChangeAt changeTime: Date = Date()) {
        guard isDiaperEnabled else { return }

        // Cancel previous
        center.removePendingNotificationRequests(withIdentifiers: [diaperReminderID])

        let fireDate = changeTime.addingTimeInterval(Double(diaperIntervalMinutes) * 60)

        // Don't schedule if fire date is in the past
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("notification.diaperTitle", comment: "")
        content.body = String(format: NSLocalizedString("notification.diaperBody %@", comment: ""), formattedInterval(diaperIntervalMinutes))
        content.sound = .default
        content.categoryIdentifier = "DIAPER_REMINDER"

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let request = UNNotificationRequest(
            identifier: diaperReminderID,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("BabyLove: Failed to schedule diaper reminder: \(error)")
            }
        }
    }

    /// Cancel any pending diaper reminder
    func cancelDiaperReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [diaperReminderID])
    }

    // MARK: - Helpers

    private func formattedInterval(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if mins == 0 {
            return String(format: NSLocalizedString("notification.hours %lld", comment: ""), hours)
        }
        return String(format: NSLocalizedString("notification.hoursMinutes %lld %lld", comment: ""), hours, mins)
    }
}
