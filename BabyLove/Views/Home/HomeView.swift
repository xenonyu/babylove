import SwiftUI
import CoreData

// MARK: - Safe Calendar Helpers

/// Calendar.date(byAdding:) technically returns Optional. These helpers
/// provide a safe fallback so we never force-unwrap in @FetchRequest
/// predicates (which are evaluated at struct-init time — a crash there
/// kills the entire view hierarchy).
private let _cal = Calendar.current
private let _today = Calendar.current.startOfDay(for: Date())
private func _safeAdd(_ component: Calendar.Component, value: Int, to date: Date) -> Date {
    _cal.date(byAdding: component, value: value, to: date) ?? date
}

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) var ctx
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var vm: TrackViewModel = TrackViewModel(context: PersistenceController.shared.container.viewContext)

    @State private var showFeedingLog  = false
    @State private var showSleepLog    = false
    @State private var showDiaperLog   = false
    @State private var showGrowthLog   = false
    @State private var sleepElapsed: TimeInterval = 0
    @State private var sleepTimer: Timer?
    @State private var feedingElapsed: TimeInterval = 0
    @State private var feedingTimer: Timer?
    @State private var showEndSleepConfirm = false
    @State private var showEndFeedingConfirm = false
    @State private var showStaleSleepAlert = false
    @State private var showStaleFeedingAlert = false
    @State private var staleTimerDuration = ""
    /// Incremented every 60s to force "time since" labels to re-evaluate
    @State private var minuteTick: Int = 0
    @State private var minuteTimer: Timer?
    @State private var selectedDate: Date = Date()
    /// Tracks the calendar day when the view was last active, so we can detect day-boundary crossings
    @State private var lastActiveCalendarDay: Date = Calendar.current.startOfDay(for: Date())
    /// Set of start-of-day dates that have at least one record (within the date range window)
    @State private var activeDays: Set<Date> = []
    /// Whether the timeline is expanded to show all events (beyond the default 20)
    @State private var isTimelineExpanded = false

    // Global "last event" times — not filtered by selected day
    @State private var globalLastFeedingRecord: CDFeedingRecord?
    @State private var globalLastFeedingIsOngoing: Bool = false
    @State private var globalLastSleepRecord: CDSleepRecord?
    @State private var globalLastSleepIsOngoing: Bool = false
    @State private var globalLastDiaperRecord: CDDiaperRecord?
    @State private var globalLastGrowthRecord: CDGrowthRecord?

    // Initialize with today's predicate to avoid flashing all-time data
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.timestamp, order: .reverse)],
        predicate: NSPredicate(format: "timestamp >= %@", Calendar.current.startOfDay(for: Date()) as NSDate)
    )
    private var todayFeedings: FetchedResults<CDFeedingRecord>

    // Use overlap-based predicate so cross-midnight sleep sessions appear
    // on both days they span (e.g. 10 PM–6 AM shows on both Day 1 and Day 2).
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.startTime, order: .reverse)],
        predicate: NSPredicate(
            format: "startTime < %@ AND (endTime >= %@ OR endTime == nil)",
            _safeAdd(.day, value: 1, to: _today) as NSDate,
            _today as NSDate
        )
    )
    private var todaySleeps: FetchedResults<CDSleepRecord>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.timestamp, order: .reverse)],
        predicate: NSPredicate(format: "timestamp >= %@", Calendar.current.startOfDay(for: Date()) as NSDate)
    )
    private var todayDiapers: FetchedResults<CDDiaperRecord>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.date, order: .reverse)],
        predicate: NSPredicate(format: "date >= %@", Calendar.current.startOfDay(for: Date()) as NSDate)
    )
    private var todayGrowth: FetchedResults<CDGrowthRecord>

    // Ongoing sleep: endTime is nil means baby is currently sleeping
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.startTime, order: .reverse)],
        predicate: NSPredicate(format: "endTime == nil")
    )
    private var ongoingSleeps: FetchedResults<CDSleepRecord>

    private var ongoingSleep: CDSleepRecord? { ongoingSleeps.first }

    // Ongoing feeding: durationMinutes == 0 AND feedType is breast/pump means timer is running
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.timestamp, order: .reverse)],
        predicate: NSPredicate(format: "durationMinutes == 0 AND (feedType == %@ OR feedType == %@)", "breast", "pump")
    )
    private var ongoingFeedings: FetchedResults<CDFeedingRecord>

    private var ongoingFeeding: CDFeedingRecord? { ongoingFeedings.first }

    // 7-day and 14-day records for weekly summary
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.timestamp, order: .reverse)],
        predicate: NSPredicate(format: "timestamp >= %@",
                               _safeAdd(.day, value: -7, to: _today) as NSDate)
    )
    private var weekFeedings: FetchedResults<CDFeedingRecord>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.startTime, order: .reverse)],
        predicate: NSPredicate(format: "startTime >= %@",
                               _safeAdd(.day, value: -7, to: _today) as NSDate)
    )
    private var weekSleeps: FetchedResults<CDSleepRecord>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.timestamp, order: .reverse)],
        predicate: NSPredicate(format: "timestamp >= %@",
                               _safeAdd(.day, value: -7, to: _today) as NSDate)
    )
    private var weekDiapers: FetchedResults<CDDiaperRecord>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.timestamp, order: .reverse)],
        predicate: NSPredicate(format: "timestamp >= %@ AND timestamp < %@",
                               _safeAdd(.day, value: -14, to: _today) as NSDate,
                               _safeAdd(.day, value: -7, to: _today) as NSDate)
    )
    private var prevWeekFeedings: FetchedResults<CDFeedingRecord>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.startTime, order: .reverse)],
        predicate: NSPredicate(format: "startTime >= %@ AND startTime < %@",
                               _safeAdd(.day, value: -14, to: _today) as NSDate,
                               _safeAdd(.day, value: -7, to: _today) as NSDate)
    )
    private var prevWeekSleeps: FetchedResults<CDSleepRecord>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.timestamp, order: .reverse)],
        predicate: NSPredicate(format: "timestamp >= %@ AND timestamp < %@",
                               _safeAdd(.day, value: -14, to: _today) as NSDate,
                               _safeAdd(.day, value: -7, to: _today) as NSDate)
    )
    private var prevWeekDiapers: FetchedResults<CDDiaperRecord>

    private var baby: Baby? { appState.currentBaby }

    private var isSelectedDateToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    /// When viewing a past date, returns a timestamp on that date (at noon)
    /// so new log sheets default to the selected day. Returns nil for today
    /// (log views will use Date() as default).
    private var retroactiveDate: Date? {
        guard !isSelectedDateToday else { return nil }
        let cal = Calendar.current
        return cal.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDate)
    }

    /// Refresh predicates to reflect the selected date.
    /// Called on appear, when returning from background, and when selectedDate changes.
    private func updatePredicates() {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: selectedDate) as NSDate
        let endOfDay = (cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: selectedDate)) ?? cal.startOfDay(for: selectedDate)) as NSDate
        todayFeedings.nsPredicate = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", startOfDay, endOfDay)
        // Overlap predicate: include sleeps that started before the day ends
        // AND (ended after the day starts OR are still ongoing).
        todaySleeps.nsPredicate   = NSPredicate(format: "startTime < %@ AND (endTime >= %@ OR endTime == nil)", endOfDay, startOfDay)
        todayDiapers.nsPredicate  = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", startOfDay, endOfDay)
        todayGrowth.nsPredicate   = NSPredicate(format: "date >= %@ AND date < %@", startOfDay, endOfDay)
    }

    /// Refresh the 7-day and 14-day weekly predicates so the weekly summary
    /// stays accurate after a day-boundary crossing (e.g. app survives past midnight).
    private func updateWeeklyPredicates() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekStart = cal.date(byAdding: .day, value: -7, to: today),
              let prevWeekStart = cal.date(byAdding: .day, value: -14, to: today) else { return }

        let weekStartNS = weekStart as NSDate
        let prevWeekStartNS = prevWeekStart as NSDate
        let todayEndNS = (cal.date(byAdding: .day, value: 1, to: today) ?? today) as NSDate

        // Current week (last 7 days up to end of today — excludes future-dated records)
        weekFeedings.nsPredicate = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", weekStartNS, todayEndNS)
        // Overlap predicate: include sleeps that started before the period ends
        // AND (ended after the period starts OR are still ongoing). This captures
        // cross-midnight sessions that start before the week boundary but end during it.
        weekSleeps.nsPredicate   = NSPredicate(format: "startTime < %@ AND (endTime >= %@ OR endTime == nil)", todayEndNS, weekStartNS)
        weekDiapers.nsPredicate  = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", weekStartNS, todayEndNS)

        // Previous week (days -14 to -7)
        prevWeekFeedings.nsPredicate = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", prevWeekStartNS, weekStartNS)
        prevWeekSleeps.nsPredicate   = NSPredicate(format: "startTime < %@ AND (endTime >= %@ OR endTime == nil)", weekStartNS, prevWeekStartNS)
        prevWeekDiapers.nsPredicate  = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", prevWeekStartNS, weekStartNS)
    }

    /// Total feeding volume in ml for today (sum of all amountML values)
    private var totalFeedingVolumeML: Double {
        todayFeedings.reduce(0.0) { sum, r in sum + r.amountML }
    }

    /// Formatted feeding volume subtitle (e.g. "480 ml · 32 min" or "16.0 oz"), empty if no volume recorded
    private var feedingVolumeSubtitle: String {
        var parts: [String] = []
        // Volume total (formula, pump, solid)
        if totalFeedingVolumeML > 0 {
            let unit = appState.measurementUnit
            let display = unit.volumeFromML(totalFeedingVolumeML)
            if unit == .metric {
                parts.append("\(Int(display)) \(unit.volumeLabel)")
            } else {
                parts.append(String(format: "%.1f %@", display, unit.volumeLabel))
            }
        }
        // Total breast/pump duration (completed sessions only — skip ongoing timers)
        let totalBreastMinutes = todayFeedings.reduce(0) { sum, r in
            let ft = FeedType(rawValue: r.feedType ?? "")
            guard ft == .breast || ft == .pump, r.durationMinutes > 0 else { return sum }
            return sum + Int(r.durationMinutes)
        }
        if totalBreastMinutes > 0 {
            parts.append(DurationFormat.fromMinutes(totalBreastMinutes))
        }
        // Last breast side (helps moms remember which side to use next)
        if let lastSide = lastBreastSide {
            parts.append(String(format: NSLocalizedString("home.lastSide %@", comment: ""), lastSide.displayName))
        }
        // Average feeding interval (only meaningful with 2+ completed feedings)
        if let avgText = avgFeedingIntervalText {
            parts.append(String(format: NSLocalizedString("home.every %@", comment: ""), avgText))
        }
        return parts.joined(separator: " · ")
    }

    /// Average interval in minutes between consecutive feedings today.
    /// Returns nil when fewer than 2 feedings exist or all have the same timestamp.
    private var avgFeedingIntervalMinutes: Int? {
        // Collect sorted timestamps (ascending), skipping ongoing timers
        // An ongoing breast/pump feeding (durationMinutes == 0) has just been started
        // and should not be included as it skews the interval calculation.
        let timestamps = todayFeedings
            .filter { !Self.isFeedingOngoing($0) }
            .compactMap { $0.timestamp }
            .sorted()
        guard timestamps.count >= 2 else { return nil }
        // Sum of intervals between consecutive feedings
        var totalInterval: TimeInterval = 0
        for i in 1..<timestamps.count {
            totalInterval += timestamps[i].timeIntervalSince(timestamps[i - 1])
        }
        let avgMinutes = Int(totalInterval / Double(timestamps.count - 1) / 60)
        return avgMinutes > 0 ? avgMinutes : nil
    }

    /// Human-readable average feeding interval, localized (e.g. "2h 15m", "2時間15分")
    private var avgFeedingIntervalText: String? {
        guard let mins = avgFeedingIntervalMinutes else { return nil }
        return DurationFormat.fromMinutes(mins)
    }

    /// The side used in the most recent breast/pump feeding today
    private var lastBreastSide: BreastSide? {
        for r in todayFeedings {
            let ft = FeedType(rawValue: r.feedType ?? "")
            if ft == .breast || ft == .pump,
               let sideRaw = r.breastSide, !sideRaw.isEmpty,
               let s = BreastSide(rawValue: sideRaw) {
                return s
            }
        }
        return nil
    }

    /// Short "time since last" string for a given date, e.g. "32m ago", "1h 5m ago"
    private static func timeSinceText(from date: Date?) -> String {
        guard let date else { return "" }
        let seconds = Int(Date().timeIntervalSince(date))
        guard seconds >= 0 else { return "" }
        if seconds < 60 { return NSLocalizedString("home.justNow", comment: "") }
        let minutes = seconds / 60
        if minutes < 60 { return String(format: NSLocalizedString("home.minsAgo %lld", comment: ""), minutes) }
        let hours = minutes / 60
        let remMins = minutes % 60
        if hours < 24 {
            return remMins > 0
                ? String(format: NSLocalizedString("home.hoursMinAgo %lld %lld", comment: ""), hours, remMins)
                : String(format: NSLocalizedString("home.hoursAgo %lld", comment: ""), hours)
        }
        let days = hours / 24
        return String(format: NSLocalizedString("home.daysAgo %lld", comment: ""), days)
    }

    /// Time since last feeding (global — not limited to selected day), or "feeding now" if ongoing.
    /// References `minuteTick` so the label refreshes every 60 seconds.
    private var feedingTimeSince: String {
        _ = minuteTick
        if globalLastFeedingIsOngoing { return NSLocalizedString("home.feedingNow", comment: "") }
        return Self.timeSinceText(from: globalLastFeedingRecord?.timestamp)
    }

    /// Time since last sleep ended (global), or "sleeping now" if ongoing.
    /// References `minuteTick` so the label refreshes every 60 seconds.
    private var sleepTimeSince: String {
        _ = minuteTick
        if globalLastSleepIsOngoing { return NSLocalizedString("home.sleepingNow", comment: "") }
        let sleepEndDate = globalLastSleepRecord?.endTime
        return Self.timeSinceText(from: sleepEndDate)
    }

    /// Time since last diaper change (global).
    /// References `minuteTick` so the label refreshes every 60 seconds.
    private var diaperTimeSince: String {
        _ = minuteTick
        return Self.timeSinceText(from: globalLastDiaperRecord?.timestamp)
    }

    // MARK: - Time-Since Urgency
    /// Computes visual urgency for feeding: >3h = warning, >5h = overdue.
    /// Ongoing feedings always show normal (baby is being fed right now).
    private var feedingUrgency: TimeSinceUrgency {
        _ = minuteTick
        if globalLastFeedingIsOngoing { return .normal }
        return Self.urgency(from: globalLastFeedingRecord?.timestamp,
                            warningMinutes: 180, overdueMinutes: 300)
    }

    /// Computes visual urgency for sleep: >5h awake = warning, >7h = overdue.
    /// Ongoing sleep always shows normal.
    private var sleepUrgency: TimeSinceUrgency {
        _ = minuteTick
        if globalLastSleepIsOngoing { return .normal }
        let ref = globalLastSleepRecord?.endTime
        return Self.urgency(from: ref, warningMinutes: 300, overdueMinutes: 420)
    }

    /// Computes visual urgency for diaper: >3h = warning, >5h = overdue.
    private var diaperUrgency: TimeSinceUrgency {
        _ = minuteTick
        return Self.urgency(from: globalLastDiaperRecord?.timestamp,
                            warningMinutes: 180, overdueMinutes: 300)
    }

    /// Generic urgency mapper: returns `.normal` / `.warning` / `.overdue`
    /// based on minutes since the given date.
    private static func urgency(from date: Date?,
                                warningMinutes: Int,
                                overdueMinutes: Int) -> TimeSinceUrgency {
        guard let date else { return .normal }
        let elapsed = Int(Date().timeIntervalSince(date)) / 60
        if elapsed >= overdueMinutes { return .overdue }
        if elapsed >= warningMinutes { return .warning }
        return .normal
    }

    /// Diaper breakdown subtitle (e.g. "3💧 2💩")
    private var diaperBreakdownSubtitle: String {
        guard !todayDiapers.isEmpty else { return "" }
        var wet = 0, dirty = 0
        for r in todayDiapers {
            switch DiaperType(rawValue: r.diaperType ?? "") {
            case .wet:   wet += 1
            case .dirty: dirty += 1
            case .both:  wet += 1; dirty += 1
            case .dry, .none: break
            }
        }
        var parts: [String] = []
        if wet > 0   { parts.append("\(wet)💧") }
        if dirty > 0 { parts.append("\(dirty)💩") }
        return parts.joined(separator: " ")
    }

    // MARK: - Smart Daily Summary

    /// Generates a human-readable one-liner summarizing the day's activity.
    /// Returns nil when there's no data at all for the selected day.
    private var dailySummaryText: String? {
        let feedCount = todayFeedings.count
        let sleepMins = totalSleepMinutes
        let diaperCount = todayDiapers.count
        let growthCount = todayGrowth.count

        guard feedCount > 0 || sleepMins > 0 || diaperCount > 0 || growthCount > 0 else { return nil }

        let babyName = baby?.name ?? "Baby"
        var parts: [String] = []

        // Feedings
        if feedCount > 0 {
            let feedKey = feedCount == 1 ? "home.summary.feedingsSingular %lld" : "home.summary.feedingsPlural %lld"
            var feedPart = String(format: NSLocalizedString(feedKey, comment: ""), feedCount)
            if totalFeedingVolumeML > 0 {
                let unit = appState.measurementUnit
                let display = unit.volumeFromML(totalFeedingVolumeML)
                if unit == .metric {
                    feedPart += " (\(Int(display)) \(unit.volumeLabel))"
                } else {
                    feedPart += " (\(String(format: "%.1f", display)) \(unit.volumeLabel))"
                }
            }
            parts.append(feedPart)
        }

        // Sleep
        if sleepMins > 0 {
            let sleepStr = DurationFormat.fromMinutes(sleepMins)
            parts.append(String(format: NSLocalizedString("home.summary.sleepOf %@", comment: ""), sleepStr))
        }

        // Diapers
        if diaperCount > 0 {
            let diaperKey = diaperCount == 1 ? "home.summary.diapersSingular %lld" : "home.summary.diapersPlural %lld"
            parts.append(String(format: NSLocalizedString(diaperKey, comment: ""), diaperCount))
        }

        // Growth measurements
        if growthCount > 0 {
            let growthKey = growthCount == 1 ? "home.summary.growthSingular" : "home.summary.growthPlural %lld"
            var growthPart = growthCount == 1
                ? NSLocalizedString(growthKey, comment: "")
                : String(format: NSLocalizedString(growthKey, comment: ""), growthCount)
            // Append latest measurement value for context
            if let latest = todayGrowth.first {
                let unit = appState.measurementUnit
                if latest.weightKG > 0 {
                    let w = unit.weightFromKG(latest.weightKG)
                    growthPart += " (\(String(format: "%.2f", w)) \(unit.weightLabel))"
                } else if latest.heightCM > 0 {
                    let h = unit.lengthFromCM(latest.heightCM)
                    growthPart += " (\(String(format: "%.1f", h)) \(unit.heightLabel))"
                }
            }
            parts.append(growthPart)
        }

        // Assemble natural sentence
        guard !parts.isEmpty else { return nil }
        let andStr = NSLocalizedString("home.summary.and", comment: "")
        let commaAndStr = NSLocalizedString("home.summary.commaAnd", comment: "")
        let joined: String
        if parts.count == 1 {
            joined = parts[0]
        } else if parts.count == 2 {
            joined = "\(parts[0])\(andStr)\(parts[1])"
        } else {
            joined = "\(parts[0...(parts.count - 2)].joined(separator: ", "))\(commaAndStr)\(parts[parts.count - 1])"
        }

        var sentence: String
        if isSelectedDateToday {
            sentence = String(format: NSLocalizedString("home.summary.todayFormat %@ %@", comment: ""), babyName, joined)
        } else {
            sentence = String(format: NSLocalizedString("home.summary.pastFormat %@ %@", comment: ""), babyName, joined)
        }

        // Append average feeding interval as a helpful insight
        if feedCount >= 2, let intervalText = avgFeedingIntervalText {
            sentence += String(format: NSLocalizedString("home.summary.feedingEvery %@", comment: ""), intervalText)
        }

        return sentence
    }

    // MARK: - Quick Log Hints

    /// Contextual hint for the Feeding quick log card.
    /// References `minuteTick` so the hint refreshes every 60 seconds.
    private var quickLogFeedingHint: String? {
        _ = minuteTick
        if globalLastFeedingIsOngoing { return NSLocalizedString("home.inProgress", comment: "") }
        // Show "Next: Right/Left" if we know the last breast side
        if let lastSide = lastBreastSide, lastSide != .both {
            let nextSide = lastSide == .left ? BreastSide.right.displayName : BreastSide.left.displayName
            return String(format: NSLocalizedString("home.next %@", comment: ""), nextSide)
        }
        // Show feed type with time since for context (e.g. "Bottle · 2h ago")
        guard let record = globalLastFeedingRecord, let lastTime = record.timestamp else { return nil }
        let timeSince = Self.timeSinceText(from: lastTime)
        if let ft = FeedType(rawValue: record.feedType ?? "") {
            return "\(ft.displayName) · \(timeSince)"
        }
        return timeSince
    }

    /// Contextual hint for the Sleep quick log card.
    /// Shows the last sleep location and time elapsed (e.g. "Crib · 2h ago").
    /// References `minuteTick` so the hint refreshes every 60 seconds.
    private var quickLogSleepHint: String? {
        _ = minuteTick
        if globalLastSleepIsOngoing {
            // Show location during ongoing sleep if available (e.g. "Crib · Sleeping")
            if let loc = globalLastSleepRecord?.location,
               let sl = SleepLocation(rawValue: loc) {
                return "\(sl.displayName) · \(NSLocalizedString("home.sleepingNow", comment: ""))"
            }
            return NSLocalizedString("home.sleepingNow", comment: "")
        }
        guard let record = globalLastSleepRecord, let lastTime = record.endTime else { return nil }
        let timeSince = Self.timeSinceText(from: lastTime)
        if let loc = record.location, let sl = SleepLocation(rawValue: loc) {
            return "\(sl.displayName) · \(timeSince)"
        }
        return timeSince
    }

    /// Contextual hint for the Diaper quick log card.
    /// Shows the last diaper type and time elapsed (e.g. "💧 Wet · 2h ago").
    /// References `minuteTick` so the hint refreshes every 60 seconds.
    private var quickLogDiaperHint: String? {
        _ = minuteTick
        guard let record = globalLastDiaperRecord, let lastTime = record.timestamp else { return nil }
        let timeSince = Self.timeSinceText(from: lastTime)
        if let dtype = DiaperType(rawValue: record.diaperType ?? "") {
            return "\(dtype.icon) \(dtype.displayName) · \(timeSince)"
        }
        return timeSince
    }

    /// Contextual hint for the Growth quick log card.
    /// Shows the last measurement value and how long ago (e.g. "5.4 kg · 3d ago").
    /// Growth is measured infrequently, so showing the last value helps parents
    /// remember context and decide when to measure again.
    private var quickLogGrowthHint: String? {
        guard let record = globalLastGrowthRecord, let lastDate = record.date else { return nil }
        let timeSince = Self.timeSinceText(from: lastDate)
        let unit = appState.measurementUnit
        // Show the most prominent measurement (weight > height > head)
        let valueStr: String? = if record.weightKG > 0 {
            String(format: "%.1f %@", unit.weightFromKG(record.weightKG), unit.weightLabel)
        } else if record.heightCM > 0 {
            String(format: "%.1f %@", unit.lengthFromCM(record.heightCM), unit.heightLabel)
        } else if record.headCircumferenceCM > 0 {
            String(format: "%.1f %@", unit.lengthFromCM(record.headCircumferenceCM), unit.heightLabel)
        } else {
            nil
        }
        if let valueStr {
            return "\(valueStr) · \(timeSince)"
        }
        return timeSince
    }

    private var totalSleepMinutes: Int {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: selectedDate)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }

        return todaySleeps.reduce(0) { sum, r in
            guard let s = r.startTime else { return sum }
            // Use current time for ongoing sleep (endTime == nil)
            let e = r.endTime ?? Date()
            // Clip the sleep session to the selected day boundaries so that
            // cross-midnight sleeps only count the portion within this day.
            let clippedStart = max(s, dayStart)
            let clippedEnd = min(e, dayEnd)
            guard clippedEnd > clippedStart else { return sum }
            return sum + Int(clippedEnd.timeIntervalSince(clippedStart) / 60)
        }
    }

    private var sleepText: String {
        DurationFormat.fromMinutes(totalSleepMinutes)
    }

    /// Subtitle for the sleep stat badge: nap count + longest nap info
    private var sleepSubtitle: String {
        let count = todaySleeps.count
        guard count > 0 else { return "" }
        var parts: [String] = []
        // Nap/session count
        parts.append(count == 1 ? NSLocalizedString("home.naps.singular", comment: "") : String(format: NSLocalizedString("home.naps.plural %lld", comment: ""), count))
        // Longest nap duration (helps parents spot patterns)
        if count > 1 {
            let cal = Calendar.current
            let dayStart = cal.startOfDay(for: selectedDate)
            guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return parts.joined(separator: " · ") }
            let longestMinutes = todaySleeps.reduce(0) { best, r in
                guard let s = r.startTime else { return best }
                let e = r.endTime ?? Date()
                let clippedStart = max(s, dayStart)
                let clippedEnd = min(e, dayEnd)
                guard clippedEnd > clippedStart else { return best }
                let mins = Int(clippedEnd.timeIntervalSince(clippedStart) / 60)
                return max(best, mins)
            }
            if longestMinutes > 0 {
                let longestText = DurationFormat.fromMinutes(longestMinutes)
                parts.append(String(format: NSLocalizedString("home.naps.longest %@", comment: ""), longestText))
            }
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.blBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Baby hero card
                        babyHeroCard

                        // Date navigation bar
                        dateNavigationBar
                            .padding(.horizontal, 20)

                        // Ongoing sleep banner (only on today)
                        if isSelectedDateToday, let ongoing = ongoingSleep {
                            ongoingSleepBanner(ongoing)
                                .padding(.horizontal, 20)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Ongoing feeding banner (only on today)
                        if isSelectedDateToday, let ongoing = ongoingFeeding {
                            ongoingFeedingBanner(ongoing)
                                .padding(.horizontal, 20)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Day stats
                        VStack(spacing: 12) {
                            BLSectionHeader(title: isSelectedDateToday ? NSLocalizedString("home.todaysSummary", comment: "") : NSLocalizedString("home.daySummary", comment: ""))
                                .padding(.horizontal, 20)

                            HStack(spacing: 12) {
                                StatBadge(value: "\(todayFeedings.count)",
                                          label: NSLocalizedString("home.feedings", comment: ""),
                                          color: .blFeeding,
                                          subtitle: feedingVolumeSubtitle,
                                          timeSince: isSelectedDateToday ? feedingTimeSince : nil,
                                          timeSinceUrgency: isSelectedDateToday ? feedingUrgency : .normal,
                                          onTap: { showFeedingLog = true })
                                StatBadge(value: sleepText,
                                          label: NSLocalizedString("home.sleep", comment: ""),
                                          color: .blSleep,
                                          subtitle: sleepSubtitle,
                                          timeSince: isSelectedDateToday ? sleepTimeSince : nil,
                                          timeSinceUrgency: isSelectedDateToday ? sleepUrgency : .normal,
                                          onTap: { showSleepLog = true })
                                StatBadge(value: "\(todayDiapers.count)",
                                          label: NSLocalizedString("home.diapers", comment: ""),
                                          color: .blDiaper,
                                          subtitle: diaperBreakdownSubtitle,
                                          timeSince: isSelectedDateToday ? diaperTimeSince : nil,
                                          timeSinceUrgency: isSelectedDateToday ? diaperUrgency : .normal,
                                          onTap: { showDiaperLog = true })
                            }
                            .padding(.horizontal, 20)

                            // Smart daily summary sentence
                            if let summary = dailySummaryText {
                                HStack(spacing: 8) {
                                    Image(systemName: "text.bubble.fill")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.blPrimary.opacity(0.6))
                                    Text(summary)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.blTextSecondary)
                                        .lineLimit(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.blPrimary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .padding(.horizontal, 20)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(summary)
                            }
                        }

                        // Quick log — available for all dates (retroactive logging)
                        VStack(spacing: 12) {
                            BLSectionHeader(title: isSelectedDateToday ? NSLocalizedString("home.quickLog", comment: "") : NSLocalizedString("home.addRecord", comment: ""))
                                .padding(.horizontal, 20)

                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 12) {
                                QuickLogCard(icon: "drop.fill",
                                             label: NSLocalizedString("home.feeding", comment: ""),
                                             color: .blFeeding,
                                             hint: isSelectedDateToday ? quickLogFeedingHint : nil) { showFeedingLog = true }
                                QuickLogCard(icon: "moon.zzz.fill",
                                             label: NSLocalizedString("home.sleep", comment: ""),
                                             color: .blSleep,
                                             hint: isSelectedDateToday ? quickLogSleepHint : nil) { showSleepLog = true }
                                QuickLogCard(icon: "oval.fill",
                                             label: NSLocalizedString("home.diaper", comment: ""),
                                             color: .blDiaper,
                                             hint: isSelectedDateToday ? quickLogDiaperHint : nil) { showDiaperLog = true }
                                QuickLogCard(icon: "chart.bar.fill",
                                             label: NSLocalizedString("home.growth", comment: ""),
                                             color: .blGrowth,
                                             hint: isSelectedDateToday ? quickLogGrowthHint : nil) { showGrowthLog = true }
                            }
                            .padding(.horizontal, 20)
                        }

                        // Weekly summary (only on today view, only if there's any data)
                        if isSelectedDateToday && (!weekFeedings.isEmpty || !weekSleeps.isEmpty || !weekDiapers.isEmpty) {
                            weeklySummaryCard
                        }

                        // Recent activity or empty state
                        if !todayFeedings.isEmpty || !todaySleeps.isEmpty || !todayDiapers.isEmpty || !todayGrowth.isEmpty {
                            recentActivitySection
                        } else {
                            emptyDaySection
                        }

                        Spacer(minLength: 100)
                    }
                    .padding(.top, 16)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 50, coordinateSpace: .local)
                        .onEnded { gesture in
                            let horizontal = gesture.translation.width
                            let vertical = gesture.translation.height
                            // Only trigger if swipe is more horizontal than vertical
                            guard abs(horizontal) > abs(vertical) * 1.5 else { return }
                            if horizontal > 0 {
                                navigateToPreviousDay()
                            } else {
                                navigateToNextDay()
                            }
                        }
                )
            }
            .navigationBarHidden(true)
            .onAppear {
                updatePredicates()
                updateWeeklyPredicates()
                refreshGlobalLastTimes()
                refreshActiveDays()
                startSleepTimerIfNeeded()
                startFeedingTimerIfNeeded()
                startMinuteTimer()
            }
            .onDisappear {
                stopSleepTimer()
                stopFeedingTimer()
                stopMinuteTimer()
            }
            .onChange(of: selectedDate) { _, _ in
                isTimelineExpanded = false
                withAnimation(.easeInOut(duration: 0.2)) {
                    updatePredicates()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    // Detect day-boundary crossing: if the calendar day changed
                    // since the view was last active, snap back to today so the
                    // user doesn't open the app to a stale past-day view.
                    let today = Calendar.current.startOfDay(for: Date())
                    if today != lastActiveCalendarDay {
                        lastActiveCalendarDay = today
                        selectedDate = Date()
                        // Weekly windows shifted — refresh their predicates
                        updateWeeklyPredicates()
                    }
                    updatePredicates()
                    refreshGlobalLastTimes()
                    refreshActiveDays()
                    startSleepTimerIfNeeded()
                    startFeedingTimerIfNeeded()
                    startMinuteTimer()
                    // Force an immediate refresh so labels are correct when returning
                    minuteTick &+= 1
                    // Warn about stale timers (>4 hours) the user may have forgotten
                    checkForStaleTimers()
                } else if phase == .background {
                    stopSleepTimer()
                    stopFeedingTimer()
                    stopMinuteTimer()
                }
            }
            .onChange(of: todayFeedings.count) { _, _ in refreshGlobalLastTimes(); refreshActiveDays() }
            .onChange(of: todaySleeps.count) { _, _ in refreshGlobalLastTimes(); refreshActiveDays() }
            .onChange(of: todayDiapers.count) { _, _ in refreshGlobalLastTimes(); refreshActiveDays() }
            .onChange(of: todayGrowth.count) { _, _ in refreshGlobalLastTimes(); refreshActiveDays() }
            .onChange(of: ongoingSleeps.count) { _, count in
                refreshGlobalLastTimes()
                if count > 0 {
                    startSleepTimerIfNeeded()
                } else {
                    stopSleepTimer()
                }
            }
            .onChange(of: ongoingFeedings.count) { _, count in
                refreshGlobalLastTimes()
                if count > 0 {
                    startFeedingTimerIfNeeded()
                } else {
                    stopFeedingTimer()
                }
            }
        }
        .sheet(isPresented: $showFeedingLog) {
            FeedingLogView(vm: vm, initialDate: retroactiveDate)
        }
        .sheet(isPresented: $showSleepLog) {
            SleepLogView(vm: vm, initialDate: retroactiveDate)
        }
        .sheet(isPresented: $showDiaperLog) {
            DiaperLogView(vm: vm, initialDate: retroactiveDate)
        }
        .sheet(isPresented: $showGrowthLog) {
            GrowthLogView(vm: vm, initialDate: retroactiveDate)
        }
        // Timeline edit sheets
        .sheet(item: $feedingToEdit) { record in
            FeedingLogView(vm: vm, editingRecord: record)
        }
        .sheet(item: $sleepToEdit) { record in
            SleepLogView(vm: vm, editingRecord: record)
        }
        .sheet(item: $diaperToEdit) { record in
            DiaperLogView(vm: vm, editingRecord: record)
        }
        .sheet(item: $growthToEdit) { record in
            GrowthLogView(vm: vm, editingRecord: record)
        }
        // Timeline delete confirmation
        .alert(NSLocalizedString("home.deleteRecord", comment: ""), isPresented: Binding(
            get: { timelineRecordToDelete != nil },
            set: { if !$0 { timelineRecordToDelete = nil } }
        )) {
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { timelineRecordToDelete = nil }
            Button(NSLocalizedString("home.delete", comment: ""), role: .destructive) {
                Haptic.warning()
                if let record = timelineRecordToDelete {
                    let (msg, icon, color): (String, String, Color) = {
                        if record is CDFeedingRecord {
                            return (NSLocalizedString("home.feedingDeleted", comment: ""), "trash.fill", Color.blFeeding)
                        } else if record is CDSleepRecord {
                            return (NSLocalizedString("home.sleepDeleted", comment: ""), "trash.fill", Color.blSleep)
                        } else if record is CDDiaperRecord {
                            return (NSLocalizedString("home.diaperDeleted", comment: ""), "trash.fill", Color.blDiaper)
                        } else if record is CDGrowthRecord {
                            return (NSLocalizedString("home.growthDeleted", comment: ""), "trash.fill", Color.blGrowth)
                        }
                        return (NSLocalizedString("home.recordDeleted", comment: ""), "trash.fill", Color.blPrimary)
                    }()
                    let success = vm.deleteObject(record, in: ctx)
                    if success {
                        withAnimation { /* row removed */ }
                        appState.showToast(msg, icon: icon, color: color)
                    } else {
                        Haptic.error()
                        appState.showToast(String(localized: "common.deleteFailed"), icon: "exclamationmark.triangle.fill", color: .red)
                    }
                }
                timelineRecordToDelete = nil
            }
        } message: {
            Text(NSLocalizedString("home.deleteConfirmMsg", comment: ""))
        }
        // End sleep timer confirmation
        .alert(NSLocalizedString("home.endSleepQ", comment: ""), isPresented: $showEndSleepConfirm) {
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("home.endSleep", comment: "")) {
                endOngoingSleep()
            }
        } message: {
            Text(String(format: NSLocalizedString("home.endSleepMsg %@ %@", comment: ""), elapsedText, appState.currentBaby?.name ?? "baby"))
        }
        // End feeding timer confirmation
        .alert(NSLocalizedString("home.endFeedingQ", comment: ""), isPresented: $showEndFeedingConfirm) {
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("home.endFeeding", comment: "")) {
                endOngoingFeeding()
            }
        } message: {
            let feedType = FeedType(rawValue: ongoingFeeding?.feedType ?? "")?.displayName ?? NSLocalizedString("home.feeding", comment: "")
            Text(String(format: NSLocalizedString("home.endFeedingMsg %@ %@ %@", comment: ""), feedingElapsedText, feedType.lowercased(), appState.currentBaby?.name ?? "baby"))
        }
        // Stale sleep timer warning
        .alert(NSLocalizedString("home.sleepTimerStale", comment: ""), isPresented: $showStaleSleepAlert) {
            Button(NSLocalizedString("home.keepRunning", comment: "")) {}
            Button(NSLocalizedString("home.endSleep", comment: ""), role: .destructive) {
                endOngoingSleep()
            }
        } message: {
            Text(String(format: NSLocalizedString("home.sleepTimerStaleMsg %@ %@", comment: ""), appState.currentBaby?.name ?? "Baby", staleTimerDuration))
        }
        // Stale feeding timer warning
        .alert(NSLocalizedString("home.feedingTimerStale", comment: ""), isPresented: $showStaleFeedingAlert) {
            Button(NSLocalizedString("home.keepRunning", comment: "")) {}
            Button(NSLocalizedString("home.endFeeding", comment: ""), role: .destructive) {
                endOngoingFeeding()
            }
        } message: {
            Text(String(format: NSLocalizedString("home.feedingTimerStaleMsg %@ %@", comment: ""), appState.currentBaby?.name ?? "Baby", staleTimerDuration))
        }
    }

    // MARK: - Global Last-Event Fetch

    /// Fetch the absolute most recent event for each category (across all days).
    /// This ensures "time since last" is correct even at the start of a new day.
    private func refreshGlobalLastTimes() {
        let ctx = PersistenceController.shared.container.viewContext

        // Last feeding (any day)
        let feedReq: NSFetchRequest<CDFeedingRecord> = CDFeedingRecord.fetchRequest()
        feedReq.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        feedReq.fetchLimit = 1
        if let lastFeeding = (try? ctx.fetch(feedReq))?.first {
            globalLastFeedingRecord = lastFeeding
            // An ongoing breast/pump feeding has durationMinutes == 0
            let ft = FeedType(rawValue: lastFeeding.feedType ?? "")
            let isTimerType = ft == .breast || ft == .pump
            globalLastFeedingIsOngoing = isTimerType && lastFeeding.durationMinutes == 0
        } else {
            globalLastFeedingRecord = nil
            globalLastFeedingIsOngoing = false
        }

        // Last sleep (any day)
        let sleepReq: NSFetchRequest<CDSleepRecord> = CDSleepRecord.fetchRequest()
        sleepReq.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: false)]
        sleepReq.fetchLimit = 1
        if let lastSleep = (try? ctx.fetch(sleepReq))?.first {
            globalLastSleepRecord = lastSleep
            globalLastSleepIsOngoing = lastSleep.endTime == nil
        } else {
            globalLastSleepRecord = nil
            globalLastSleepIsOngoing = false
        }

        // Last diaper (any day)
        let diaperReq: NSFetchRequest<CDDiaperRecord> = CDDiaperRecord.fetchRequest()
        diaperReq.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        diaperReq.fetchLimit = 1
        globalLastDiaperRecord = (try? ctx.fetch(diaperReq))?.first

        // Last growth measurement (any day)
        let growthReq: NSFetchRequest<CDGrowthRecord> = CDGrowthRecord.fetchRequest()
        growthReq.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        growthReq.fetchLimit = 1
        globalLastGrowthRecord = (try? ctx.fetch(growthReq))?.first
    }

    // MARK: - Active Days Indicators

    /// Refresh the set of days that have at least one record (feeding, sleep, or diaper)
    /// within the date navigation range (last 14 days).
    private func refreshActiveDays() {
        let ctx = PersistenceController.shared.container.viewContext
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let rangeStart = cal.date(byAdding: .day, value: -13, to: today) else { return }
        let rangeStartNS = rangeStart as NSDate

        var days = Set<Date>()

        // Feeding timestamps
        let feedReq: NSFetchRequest<CDFeedingRecord> = CDFeedingRecord.fetchRequest()
        feedReq.predicate = NSPredicate(format: "timestamp >= %@", rangeStartNS)
        feedReq.propertiesToFetch = ["timestamp"]
        if let results = try? ctx.fetch(feedReq) {
            for r in results {
                if let ts = r.timestamp { days.insert(cal.startOfDay(for: ts)) }
            }
        }

        // Sleep records — use overlap predicate to capture cross-midnight sessions
        // that started before the range but ended within it (e.g. 10 PM day -14 → 6 AM day -13).
        // Also insert BOTH start day and end day so overnight sleeps mark both days as active.
        let rangeEndNS = (cal.date(byAdding: .day, value: 1, to: today) ?? today) as NSDate
        let sleepReq: NSFetchRequest<CDSleepRecord> = CDSleepRecord.fetchRequest()
        sleepReq.predicate = NSPredicate(
            format: "startTime < %@ AND (endTime >= %@ OR endTime == nil)",
            rangeEndNS, rangeStartNS
        )
        if let results = try? ctx.fetch(sleepReq) {
            for r in results {
                if let st = r.startTime {
                    let startDay = cal.startOfDay(for: st)
                    if startDay >= rangeStart { days.insert(startDay) }
                }
                if let et = r.endTime {
                    let endDay = cal.startOfDay(for: et)
                    if endDay >= rangeStart { days.insert(endDay) }
                }
            }
        }

        // Diaper timestamps
        let diaperReq: NSFetchRequest<CDDiaperRecord> = CDDiaperRecord.fetchRequest()
        diaperReq.predicate = NSPredicate(format: "timestamp >= %@", rangeStartNS)
        diaperReq.propertiesToFetch = ["timestamp"]
        if let results = try? ctx.fetch(diaperReq) {
            for r in results {
                if let ts = r.timestamp { days.insert(cal.startOfDay(for: ts)) }
            }
        }

        // Growth dates
        let growthReq: NSFetchRequest<CDGrowthRecord> = CDGrowthRecord.fetchRequest()
        growthReq.predicate = NSPredicate(format: "date >= %@", rangeStartNS)
        growthReq.propertiesToFetch = ["date"]
        if let results = try? ctx.fetch(growthReq) {
            for r in results {
                if let d = r.date { days.insert(cal.startOfDay(for: d)) }
            }
        }

        activeDays = days
    }

    // MARK: - Sleep Timer

    private func startSleepTimerIfNeeded() {
        guard ongoingSleep != nil, sleepTimer == nil else { return }
        updateSleepElapsed()
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in updateSleepElapsed() }
        }
    }

    private func stopSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
    }

    private func updateSleepElapsed() {
        guard let start = ongoingSleep?.startTime else {
            sleepElapsed = 0
            return
        }
        sleepElapsed = Date().timeIntervalSince(start)
    }

    private var elapsedText: String {
        let total = Int(sleepElapsed)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func endOngoingSleep() {
        guard let ongoing = ongoingSleep, let id = ongoing.id else { return }
        // Capture duration before ending so the toast can report it
        let durationText = Self.humanReadableDuration(sleepElapsed)
        var ok = false
        withAnimation(.spring(response: 0.4)) {
            ok = vm.endSleepByID(id, context: ctx)
        }
        if ok {
            Haptic.success()
            stopSleepTimer()
            appState.showToast(String(format: NSLocalizedString("home.sleepEnded %@", comment: ""), durationText), icon: "sun.and.horizon.fill", color: .blSleep)
        } else {
            Haptic.error()
            appState.showToast(NSLocalizedString("home.saveFailed", comment: ""), icon: "exclamationmark.triangle.fill", color: .red)
        }
    }

    @ViewBuilder
    private func ongoingSleepBanner(_ record: CDSleepRecord) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Pulsing moon icon
                ZStack {
                    Circle()
                        .fill(Color.blSleep.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.blSleep)
                        .symbolEffect(.pulse)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("home.babySleeping", comment: ""))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.blTextPrimary)
                    if let start = record.startTime {
                        Text(String(format: NSLocalizedString("home.since %@", comment: ""), start.formatted(date: .omitted, time: .shortened)))
                            .font(.system(size: 13))
                            .foregroundColor(.blTextSecondary)
                    }
                }

                Spacer()

                // Live timer
                Text(elapsedText)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.blSleep)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Button {
                Haptic.medium()
                showEndSleepConfirm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sun.and.horizon.fill")
                        .font(.system(size: 14, weight: .medium))
                    Text(NSLocalizedString("home.endSleep", comment: ""))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.blSleep)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.blSleep.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.blSleep.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(NSLocalizedString("home.babySleeping", comment: "")), \(elapsedText)")
    }

    // MARK: - Feeding Timer

    private func startFeedingTimerIfNeeded() {
        guard ongoingFeeding != nil, feedingTimer == nil else { return }
        updateFeedingElapsed()
        feedingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in updateFeedingElapsed() }
        }
    }

    private func stopFeedingTimer() {
        feedingTimer?.invalidate()
        feedingTimer = nil
    }

    // MARK: - Stale Timer Detection

    /// Threshold in seconds after which we consider a timer "forgotten" (4 hours)
    private static let staleTimerThreshold: TimeInterval = 4 * 3600

    /// Check if any ongoing timers have been running unusually long and warn the user
    private func checkForStaleTimers() {
        // Check sleep timer first (more likely to be forgotten overnight)
        if let start = ongoingSleep?.startTime {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= Self.staleTimerThreshold {
                staleTimerDuration = Self.humanReadableDuration(elapsed)
                showStaleSleepAlert = true
                return // Show one alert at a time
            }
        }
        // Then check feeding timer
        if let start = ongoingFeeding?.timestamp {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= Self.staleTimerThreshold {
                staleTimerDuration = Self.humanReadableDuration(elapsed)
                showStaleFeedingAlert = true
            }
        }
    }

    /// Format a duration into a localized human-readable string like "5h 23m" / "5時間23分"
    private static func humanReadableDuration(_ interval: TimeInterval) -> String {
        DurationFormat.fromSeconds(interval)
    }

    // MARK: - Minute Refresh Timer (keeps "time since" labels accurate)

    private func startMinuteTimer() {
        guard minuteTimer == nil else { return }
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in minuteTick &+= 1 }
        }
    }

    private func stopMinuteTimer() {
        minuteTimer?.invalidate()
        minuteTimer = nil
    }

    private func updateFeedingElapsed() {
        guard let start = ongoingFeeding?.timestamp else {
            feedingElapsed = 0
            return
        }
        feedingElapsed = Date().timeIntervalSince(start)
    }

    private var feedingElapsedText: String {
        let total = Int(feedingElapsed)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func endOngoingFeeding() {
        guard let ongoing = ongoingFeeding, let id = ongoing.id else { return }
        // Capture duration before ending so the toast can report it
        let durationText = Self.humanReadableDuration(feedingElapsed)
        var ok = false
        withAnimation(.spring(response: 0.4)) {
            ok = vm.endFeedingByID(id, context: ctx)
        }
        if ok {
            Haptic.success()
            stopFeedingTimer()
            appState.showToast(String(format: NSLocalizedString("home.feedingEnded %@", comment: ""), durationText), icon: "checkmark.circle.fill", color: .blFeeding)
        } else {
            Haptic.error()
            appState.showToast(NSLocalizedString("home.saveFailed", comment: ""), icon: "exclamationmark.triangle.fill", color: .red)
        }
    }

    @ViewBuilder
    private func ongoingFeedingBanner(_ record: CDFeedingRecord) -> some View {
        let feedType = FeedType(rawValue: record.feedType ?? "") ?? .breast
        let side = BreastSide(rawValue: record.breastSide ?? "")

        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Pulsing icon
                ZStack {
                    Circle()
                        .fill(Color.blFeeding.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: feedType.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.blFeeding)
                        .symbolEffect(.pulse)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("home.feedingInProgress", comment: ""))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.blTextPrimary)
                    HStack(spacing: 4) {
                        Text(feedType.displayName)
                            .font(.system(size: 13))
                            .foregroundColor(.blTextSecondary)
                        if let side {
                            Text("· \(side.displayName)")
                                .font(.system(size: 13))
                                .foregroundColor(.blTextSecondary)
                        }
                        if let start = record.timestamp {
                            Text("· \(start.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 13))
                                .foregroundColor(.blTextSecondary)
                        }
                    }
                }

                Spacer()

                // Live timer
                Text(feedingElapsedText)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.blFeeding)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Button {
                Haptic.medium()
                showEndFeedingConfirm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                    Text(NSLocalizedString("home.endFeeding", comment: ""))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.blFeeding)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.blFeeding.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.blFeeding.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(NSLocalizedString("home.feedingInProgress", comment: "")), \(feedingElapsedText)")
    }

    // MARK: - Date Navigation Bar

    /// Returns the last 14 days (today + 13 past days) for the date picker
    private var dateRange: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<14).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    /// The earliest date the user can navigate to: the later of 13 days ago
    /// or the baby's birth date (no point showing dates before birth).
    private var earliestNavigableDate: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let rangeStart = cal.date(byAdding: .day, value: -13, to: today) ?? today
        if let birth = baby?.birthDate {
            let birthStart = cal.startOfDay(for: birth)
            return max(rangeStart, birthStart)
        }
        return rangeStart
    }

    /// Whether the left chevron should be disabled (already at earliest date)
    private var canNavigateBack: Bool {
        Calendar.current.startOfDay(for: selectedDate) > earliestNavigableDate
    }

    /// Navigate to the previous day (if within range)
    private func navigateToPreviousDay() {
        let cal = Calendar.current
        guard let prev = cal.date(byAdding: .day, value: -1, to: selectedDate),
              cal.startOfDay(for: prev) >= earliestNavigableDate else { return }
        Haptic.selection()
        withAnimation(.easeInOut(duration: 0.2)) { selectedDate = prev }
    }

    /// Navigate to the next day (capped at today)
    private func navigateToNextDay() {
        guard !isSelectedDateToday else { return }
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: selectedDate) ?? Date()
        let capped = min(tomorrow, Date())
        Haptic.selection()
        withAnimation(.easeInOut(duration: 0.2)) { selectedDate = capped }
    }

    private var dateNavigationBar: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    navigateToPreviousDay()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(canNavigateBack ? .blPrimary : .blTextTertiary)
                        .frame(width: 32, height: 32)
                }
                .disabled(!canNavigateBack)
                .accessibilityLabel(NSLocalizedString("a11y.previousDay", comment: ""))
                .accessibilityHint(canNavigateBack ? NSLocalizedString("a11y.previousDayHint", comment: "") : NSLocalizedString("a11y.earliestDate", comment: ""))

                Spacer()

                Text(dateHeaderText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.blTextPrimary)
                    .contentTransition(.numericText())

                Spacer()

                if isSelectedDateToday {
                    // Placeholder to keep layout balanced
                    Color.clear.frame(width: 32, height: 32)
                } else {
                    Button {
                        navigateToNextDay()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.blPrimary)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(NSLocalizedString("a11y.nextDay", comment: ""))
                    .accessibilityHint(NSLocalizedString("a11y.nextDayHint", comment: ""))
                }
            }

            // Scrollable day pills
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(dateRange, id: \.self) { date in
                            let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                            let isToday = Calendar.current.isDateInToday(date)
                            let hasActivity = activeDays.contains(date)
                            Button {
                                Haptic.selection()
                                withAnimation(.easeInOut(duration: 0.2)) { selectedDate = date }
                            } label: {
                                VStack(spacing: 2) {
                                    Text(dayOfWeekText(date))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(isSelected ? .white : .blTextTertiary)
                                    Text(dayNumberText(date))
                                        .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                                        .foregroundColor(isSelected ? .white : (isToday ? .blPrimary : .blTextPrimary))
                                    // Activity indicator dot
                                    Circle()
                                        .fill(isSelected ? Color.white : Color.blPrimary)
                                        .frame(width: 5, height: 5)
                                        .opacity(hasActivity ? 1 : 0)
                                }
                                .frame(width: 40, height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(isSelected ? Color.blPrimary : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(isToday ? dateHeaderText : "\(dayOfWeekText(date)) \(dayNumberText(date))")\(hasActivity ? NSLocalizedString("a11y.dateHasActivity", comment: "") : "")")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                            .id(date)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .onAppear {
                    proxy.scrollTo(Calendar.current.startOfDay(for: selectedDate), anchor: .leading)
                }
                .onChange(of: selectedDate) { _, newDate in
                    withAnimation {
                        proxy.scrollTo(Calendar.current.startOfDay(for: newDate), anchor: .center)
                    }
                }
            }

            // "Back to Today" button when viewing past date
            if !isSelectedDateToday {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedDate = Date() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(NSLocalizedString("home.backToToday", comment: ""))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.blPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.blPrimary.opacity(0.1))
                    .clipShape(Capsule())
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.vertical, 8)
        .blCard()
    }

    private var dateHeaderText: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDate) || cal.isDateInYesterday(selectedDate) {
            return BLDateFormatters.relativeFull.string(from: selectedDate)
        }
        return BLDateFormatters.fullWeekdayMonthDay.string(from: selectedDate)
    }

    private func dayOfWeekText(_ date: Date) -> String {
        BLDateFormatters.shortWeekday.string(from: date).uppercased()
    }

    private func dayNumberText(_ date: Date) -> String {
        BLDateFormatters.dayNumber.string(from: date)
    }

    // MARK: - Weekly Summary

    /// The actual number of days to use as divisor for the current 7-day window.
    /// If the baby is younger than 7 days, we use their age instead to avoid
    /// artificially low averages for new users. Always at least 1.
    private var currentWeekActiveDays: Double {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekStart = cal.date(byAdding: .day, value: -7, to: today) ?? today
        // If we have a baby birth date, cap the window to days since birth
        if let birth = baby?.birthDate {
            let birthStart = cal.startOfDay(for: birth)
            // How many days from the later of (weekStart, birthStart) to today
            let effectiveStart = max(weekStart, birthStart)
            // dateComponents returns day-boundary crossings (exclusive end),
            // so add 1 for inclusive day count: born today → 1 day of data
            let days = (cal.dateComponents([.day], from: effectiveStart, to: today).day ?? 6) + 1
            return Double(max(1, min(7, days)))
        }
        return 7.0
    }

    /// The actual number of days to use as divisor for the previous 7-day window.
    /// Note: prevWeekEnd is exclusive (predicate uses `< weekStart`), so
    /// dateComponents already gives the correct inclusive day count without +1.
    private var prevWeekActiveDays: Double {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let prevWeekStart = cal.date(byAdding: .day, value: -14, to: today) ?? today
        let prevWeekEnd = cal.date(byAdding: .day, value: -7, to: today) ?? today
        if let birth = baby?.birthDate {
            let birthStart = cal.startOfDay(for: birth)
            // If baby wasn't born during the prev week, the full 7 days apply
            // If baby was born during prev week, only count days since birth
            if birthStart >= prevWeekEnd {
                // Baby wasn't born yet during prev week — no valid data
                return 7.0 // won't matter since prevWeek data will be empty
            }
            let effectiveStart = max(prevWeekStart, birthStart)
            let days = cal.dateComponents([.day], from: effectiveStart, to: prevWeekEnd).day ?? 7
            return Double(max(1, min(7, days)))
        }
        return 7.0
    }

    /// Average feedings per day this week
    private var weekAvgFeedings: Double {
        guard !weekFeedings.isEmpty else { return 0 }
        return Double(weekFeedings.count) / currentWeekActiveDays
    }

    /// Total feeding volume in ml for the current week (formula + pump amountML only)
    private var weekTotalVolumeML: Double {
        weekFeedings.reduce(0.0) { sum, r in sum + r.amountML }
    }

    /// Average daily feeding volume in ml this week (for bottle-feeding parents)
    private var weekAvgVolumeMlPerDay: Double {
        guard weekTotalVolumeML > 0 else { return 0 }
        return weekTotalVolumeML / currentWeekActiveDays
    }

    /// Total feeding volume in ml for the previous week
    private var prevWeekTotalVolumeML: Double {
        prevWeekFeedings.reduce(0.0) { sum, r in sum + r.amountML }
    }

    /// Average daily feeding volume in ml previous week
    private var prevWeekAvgVolumeMlPerDay: Double {
        guard prevWeekTotalVolumeML > 0 else { return 0 }
        return prevWeekTotalVolumeML / prevWeekActiveDays
    }

    /// Average sleep hours per day this week
    /// Note: Ongoing sessions (endTime == nil) are skipped so the running
    /// timer doesn't inflate the weekly average — consistent with prevWeek.
    /// Sleep durations are clamped to the week boundaries so cross-boundary
    /// sessions only contribute the portion that falls within this week.
    private var weekAvgSleepHours: Double {
        guard !weekSleeps.isEmpty else { return 0 }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let periodStart = cal.date(byAdding: .day, value: -7, to: today),
              let periodEnd = cal.date(byAdding: .day, value: 1, to: today) else { return 0 }
        let completedSleeps = weekSleeps.filter { $0.endTime != nil }
        guard !completedSleeps.isEmpty else { return 0 }
        let totalMinutes = completedSleeps.reduce(0) { sum, r in
            guard let s = r.startTime, let e = r.endTime else { return sum }
            let clampedStart = max(s, periodStart)
            let clampedEnd = min(e, periodEnd)
            guard clampedEnd > clampedStart else { return sum }
            return sum + Int(clampedEnd.timeIntervalSince(clampedStart) / 60)
        }
        return Double(totalMinutes) / 60.0 / currentWeekActiveDays
    }

    /// Average diapers per day this week
    private var weekAvgDiapers: Double {
        guard !weekDiapers.isEmpty else { return 0 }
        return Double(weekDiapers.count) / currentWeekActiveDays
    }

    /// Wet/dirty diaper breakdown for weekly summary (e.g. "Total 42 · 28💧 18💩")
    private var weekDiaperBreakdownText: String {
        guard !weekDiapers.isEmpty else { return "" }
        var wet = 0, dirty = 0
        for r in weekDiapers {
            switch DiaperType(rawValue: r.diaperType ?? "") {
            case .wet:   wet += 1
            case .dirty: dirty += 1
            case .both:  wet += 1; dirty += 1
            case .dry, .none: break
            }
        }
        var parts: [String] = []
        parts.append(String(format: NSLocalizedString("home.weekly.total %lld", comment: ""), weekDiapers.count))
        if wet > 0   { parts.append("\(wet)💧") }
        if dirty > 0 { parts.append("\(dirty)💩") }
        return parts.joined(separator: " · ")
    }

    /// Average feedings per day previous week
    private var prevWeekAvgFeedings: Double {
        guard !prevWeekFeedings.isEmpty else { return 0 }
        return Double(prevWeekFeedings.count) / prevWeekActiveDays
    }

    /// Average sleep hours per day previous week
    /// Note: Ongoing sessions (endTime == nil) are skipped because historical
    /// averages must not use the current time as a stand-in end time.
    /// Sleep durations are clamped to the previous week boundaries.
    private var prevWeekAvgSleepHours: Double {
        guard !prevWeekSleeps.isEmpty else { return 0 }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let periodStart = cal.date(byAdding: .day, value: -14, to: today),
              let periodEnd = cal.date(byAdding: .day, value: -7, to: today) else { return 0 }
        let totalMinutes = prevWeekSleeps.reduce(0) { sum, r in
            guard let s = r.startTime, let e = r.endTime else { return sum }
            let clampedStart = max(s, periodStart)
            let clampedEnd = min(e, periodEnd)
            guard clampedEnd > clampedStart else { return sum }
            return sum + Int(clampedEnd.timeIntervalSince(clampedStart) / 60)
        }
        return Double(totalMinutes) / 60.0 / prevWeekActiveDays
    }

    /// Average diapers per day previous week
    private var prevWeekAvgDiapers: Double {
        guard !prevWeekDiapers.isEmpty else { return 0 }
        return Double(prevWeekDiapers.count) / prevWeekActiveDays
    }

    /// Returns a trend icon based on comparison (up, down, or steady)
    private static func trendIcon(current: Double, previous: Double) -> (icon: String, color: Color) {
        guard previous > 0 else { return ("equal", .blTextTertiary) }
        let diff = (current - previous) / previous
        if diff > 0.1 { return ("arrow.up.right", .blFeeding) }
        if diff < -0.1 { return ("arrow.down.right", .blTeal) }
        return ("equal", .blTextTertiary)
    }

    /// Label for the weekly summary header, adjusted for babies younger than 7 days
    private var weeklySummaryTitle: String {
        let days = Int(currentWeekActiveDays)
        if days < 7 {
            if days == 1 {
                return NSLocalizedString("home.lastOneDay", comment: "")
            }
            return String(format: NSLocalizedString("home.lastNDays %lld", comment: ""), days)
        }
        return NSLocalizedString("home.thisWeek", comment: "")
    }

    private var weeklySummaryCard: some View {
        VStack(spacing: 12) {
            BLSectionHeader(title: weeklySummaryTitle)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                // Row 1: Feedings (count)
                if !weekFeedings.isEmpty {
                    weeklyRow(
                        icon: "drop.fill",
                        color: .blFeeding,
                        title: NSLocalizedString("home.weekly.feedings", comment: ""),
                        value: String(format: "%.1f", weekAvgFeedings),
                        unit: NSLocalizedString("home.weekly.perDay", comment: ""),
                        total: String(format: NSLocalizedString("home.weekly.total %lld", comment: ""), weekFeedings.count),
                        current: weekAvgFeedings,
                        previous: prevWeekAvgFeedings
                    )
                }

                // Row 1b: Feeding Volume (only shown when there's bottle/pump volume data)
                if weekTotalVolumeML > 0 {
                    Divider().padding(.leading, 60)
                    let unit = appState.measurementUnit
                    let avgDisplay = unit.volumeFromML(weekAvgVolumeMlPerDay)
                    let totalDisplay = unit.volumeFromML(weekTotalVolumeML)
                    let valueText = unit == .metric
                        ? "\(Int(avgDisplay.rounded()))"
                        : String(format: "%.1f", avgDisplay)
                    let totalNumText = unit == .metric
                        ? "\(Int(totalDisplay.rounded()))"
                        : String(format: "%.1f", totalDisplay)
                    let totalText = String(format: NSLocalizedString("home.weekly.volumeTotal %@ %@", comment: ""), totalNumText, unit.volumeLabel)
                    weeklyRow(
                        icon: "cross.vial.fill",
                        color: .blFeeding,
                        title: NSLocalizedString("home.weekly.volume", comment: ""),
                        value: valueText,
                        unit: "\(unit.volumeLabel)\(NSLocalizedString("home.weekly.perDay", comment: ""))",
                        total: totalText,
                        current: weekAvgVolumeMlPerDay,
                        previous: prevWeekAvgVolumeMlPerDay
                    )
                }

                if !weekFeedings.isEmpty && !weekSleeps.isEmpty {
                    Divider().padding(.leading, 60)
                }

                // Row 2: Sleep
                if !weekSleeps.isEmpty {
                    weeklyRow(
                        icon: "moon.zzz.fill",
                        color: .blSleep,
                        title: NSLocalizedString("home.weekly.sleep", comment: ""),
                        value: String(format: NSLocalizedString("home.weekly.hoursValue %@", comment: ""), String(format: "%.1f", weekAvgSleepHours)),
                        unit: NSLocalizedString("home.weekly.perDay", comment: ""),
                        total: String(format: NSLocalizedString("home.weekly.naps %lld", comment: ""), weekSleeps.count),
                        current: weekAvgSleepHours,
                        previous: prevWeekAvgSleepHours
                    )
                }

                if (!weekFeedings.isEmpty || !weekSleeps.isEmpty) && !weekDiapers.isEmpty {
                    Divider().padding(.leading, 60)
                }

                // Row 3: Diapers (with wet/dirty breakdown)
                if !weekDiapers.isEmpty {
                    weeklyRow(
                        icon: "oval.fill",
                        color: .blDiaper,
                        title: NSLocalizedString("home.weekly.diapers", comment: ""),
                        value: String(format: "%.1f", weekAvgDiapers),
                        unit: NSLocalizedString("home.weekly.perDay", comment: ""),
                        total: weekDiaperBreakdownText,
                        current: weekAvgDiapers,
                        previous: prevWeekAvgDiapers
                    )
                }
            }
            .blCard()
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func weeklyRow(icon: String, color: Color, title: String, value: String, unit: String, total: String, current: Double, previous: Double) -> some View {
        let trend = Self.trendIcon(current: current, previous: previous)
        let trendDescription = Self.trendDescription(current: current, previous: previous)
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blTextPrimary)
                Text(total)
                    .font(.system(size: 11))
                    .foregroundColor(.blTextTertiary)
            }

            Spacer()

            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.blTextTertiary)
            }

            if previous > 0 {
                Image(systemName: trend.icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(trend.color)
                    .frame(width: 18)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(weeklyRowAccessibilityLabel(title: title, value: value, unit: unit, total: total, trend: trendDescription))
    }

    /// Build a human-readable VoiceOver label for a weekly summary row.
    private func weeklyRowAccessibilityLabel(title: String, value: String, unit: String, total: String, trend: String) -> String {
        var parts = ["\(title), \(value) \(unit)"]
        if !total.isEmpty { parts.append(total) }
        if !trend.isEmpty { parts.append(trend) }
        return parts.joined(separator: ", ")
    }

    /// Human-readable trend description for VoiceOver (e.g. "up 15% from last week")
    private static func trendDescription(current: Double, previous: Double) -> String {
        guard previous > 0 else { return "" }
        let diff = (current - previous) / previous
        let pct = Int(abs(diff * 100))
        if diff > 0.1 {
            return String(format: NSLocalizedString("home.weekly.upPct %lld", comment: ""), pct)
        } else if diff < -0.1 {
            return String(format: NSLocalizedString("home.weekly.downPct %lld", comment: ""), pct)
        } else {
            return NSLocalizedString("home.weekly.same", comment: "")
        }
    }

    // MARK: - Baby Hero Card

    private var babyHeroCard: some View {
        HStack(spacing: 16) {
            // Avatar
            if let baby {
                BabyAvatarView(baby: baby, size: 64)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.blPrimary.opacity(0.2))
                        .frame(width: 64, height: 64)
                    Text("🍼")
                        .font(.system(size: 32))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(baby?.name ?? "Baby")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.blTextPrimary)
                // Show baby's age at the selected date, not always today
                Text(heroAgeText)
                    .font(.system(size: 15))
                    .foregroundColor(.blTextSecondary)
                // Show the selected date, not always today
                Text(selectedDate.formatted(date: .complete, time: .omitted))
                    .font(.system(size: 12))
                    .foregroundColor(.blTextTertiary)
            }

            Spacer()
        }
        .padding(20)
        .blCard()
        .padding(.horizontal, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(babyHeroAccessibilityLabel)
    }

    /// Age text for the hero card — shows baby's age at the selected date.
    /// When viewing a past date, this reflects how old the baby was on that day.
    private var heroAgeText: String {
        guard let baby else { return "" }
        if isSelectedDateToday {
            return baby.ageText
        } else {
            return baby.ageText(at: selectedDate)
        }
    }

    private var babyHeroAccessibilityLabel: String {
        var parts: [String] = []
        parts.append(baby?.name ?? "Baby")
        if let baby {
            let ageStr = isSelectedDateToday ? baby.localizedAge : baby.ageText(at: selectedDate)
            if !ageStr.isEmpty { parts.append(ageStr) }
        }
        parts.append(selectedDate.formatted(date: .complete, time: .omitted))
        return parts.joined(separator: ", ")
    }

    // MARK: - Empty Day State

    private var emptyDaySection: some View {
        VStack(spacing: 16) {
            BLSectionHeader(title: NSLocalizedString("home.recentActivity", comment: ""))
                .padding(.horizontal, 20)

            VStack(spacing: 14) {
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blPrimary.opacity(0.5), .blGrowth.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.top, 4)

                Text(isSelectedDateToday ? NSLocalizedString("home.noActivityToday", comment: "") : NSLocalizedString("home.noActivityThisDay", comment: ""))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blTextSecondary)

                Text(isSelectedDateToday
                     ? String(format: NSLocalizedString("home.tapToStart %@", comment: ""), baby?.name ?? "baby")
                     : String(format: NSLocalizedString("home.noRecordsLogged %@", comment: ""), baby?.name ?? "baby"))
                    .font(.system(size: 14))
                    .foregroundColor(.blTextTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .blCard()
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Recent Activity

    // MARK: - Time Since Helpers

    /// Format a time interval as a human-readable "time ago" string
    private static func timeAgoText(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return NSLocalizedString("home.justNow", comment: "").capitalized }
        let minutes = seconds / 60
        if minutes < 60 { return String(format: NSLocalizedString("home.minsAgo %lld", comment: ""), minutes) }
        let hours = minutes / 60
        let remainMinutes = minutes % 60
        if hours < 24 {
            return remainMinutes > 0
                ? String(format: NSLocalizedString("home.hoursMinAgo %lld %lld", comment: ""), hours, remainMinutes)
                : String(format: NSLocalizedString("home.hoursAgo %lld", comment: ""), hours)
        }
        let days = hours / 24
        if days == 1 {
            return BLDateFormatters.relativeShort.string(from: Date(timeIntervalSinceNow: -86400))
        }
        return String(format: NSLocalizedString("home.daysAgo %lld", comment: ""), days)
    }

    /// Whether a feeding record represents an ongoing timer (breast/pump with durationMinutes == 0).
    private static func isFeedingOngoing(_ r: CDFeedingRecord) -> Bool {
        let ft = FeedType(rawValue: r.feedType ?? "")
        let isTimerType = ft == .breast || ft == .pump
        return isTimerType && r.durationMinutes == 0
    }

    /// Build a short detail string for the last feeding (e.g. "15m · Left" or "120 ml")
    private func feedingDetail(_ r: CDFeedingRecord) -> String {
        let unit = appState.measurementUnit
        var parts: [String] = []
        if Self.isFeedingOngoing(r) {
            parts.append(NSLocalizedString("home.ongoing", comment: ""))
        } else if r.durationMinutes > 0 {
            parts.append(DurationFormat.compact(r.durationMinutes))
        }
        if r.amountML > 0 {
            let display = unit.volumeFromML(r.amountML)
            if unit == .metric {
                parts.append("\(Int(display)) \(unit.volumeLabel)")
            } else {
                parts.append(String(format: "%.1f %@", display, unit.volumeLabel))
            }
        }
        if let side = r.breastSide, !side.isEmpty {
            parts.append(BreastSide(rawValue: side)?.displayName ?? side)
        }
        return parts.joined(separator: " · ")
    }

    /// For past dates, show the record time only (no misleading "Xh ago").
    /// For today, show the relative "time ago" badge.
    private func activityTimeAgo(from date: Date?) -> String {
        guard let date else { return "" }
        if isSelectedDateToday {
            return Self.timeAgoText(from: date)
        }
        // Past date: show just the formatted time (no relative "ago")
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Activity Timeline

    // Edit / delete state for timeline context menus
    @State private var feedingToEdit: CDFeedingRecord?
    @State private var sleepToEdit: CDSleepRecord?
    @State private var diaperToEdit: CDDiaperRecord?
    @State private var growthToEdit: CDGrowthRecord?
    @State private var timelineRecordToDelete: NSManagedObject?

    /// A unified activity item for the chronological timeline.
    private struct ActivityItem: Identifiable {
        enum RecordRef {
            case feeding(CDFeedingRecord)
            case sleep(CDSleepRecord)
            case diaper(CDDiaperRecord)
            case growth(CDGrowthRecord)
        }
        let id: String  // unique key
        let date: Date
        let icon: String
        let color: Color
        let title: String
        let detail: String
        let timeLabel: String
        let notes: String?
        let record: RecordRef
    }

    /// Build a merged, reverse-chronological list of all activities for the selected day.
    private var timelineItems: [ActivityItem] {
        var items: [ActivityItem] = []

        for r in todayFeedings {
            guard let ts = r.timestamp else { continue }
            let ft = FeedType(rawValue: r.feedType ?? "")
            let isOngoing = Self.isFeedingOngoing(r)
            let title = isOngoing
                ? "\(ft?.displayName ?? NSLocalizedString("home.feeding", comment: "")) (\(NSLocalizedString("home.inProgress", comment: "").lowercased()))"
                : (ft?.displayName ?? NSLocalizedString("home.feeding", comment: ""))
            items.append(ActivityItem(
                id: "f-\(r.id?.uuidString ?? r.objectID.uriRepresentation().lastPathComponent)",
                date: ts,
                icon: isOngoing ? "drop.fill" : (ft?.icon ?? "drop.fill"),
                color: .blFeeding,
                title: title,
                detail: feedingDetail(r),
                timeLabel: ts.formatted(date: .omitted, time: .shortened),
                notes: r.notes,
                record: .feeding(r)
            ))
        }

        for r in todaySleeps {
            guard let st = r.startTime else { continue }
            let cal = Calendar.current
            let selectedDayStart = cal.startOfDay(for: selectedDate)
            let startIsOnDifferentDay = !cal.isDate(st, inSameDayAs: selectedDate)
            let detail: String = {
                var parts: [String] = []
                // Location
                if let loc = r.location, !loc.isEmpty,
                   let sl = SleepLocation(rawValue: loc) {
                    parts.append(sl.displayName)
                }
                // Duration or Ongoing
                if r.endTime == nil {
                    parts.append(NSLocalizedString("home.ongoing", comment: ""))
                } else if let e = r.endTime {
                    let mins = Int(e.timeIntervalSince(st) / 60)
                    parts.append(DurationFormat.fromMinutes(mins))
                }
                return parts.joined(separator: " · ")
            }()
            let isOngoing = r.endTime == nil
            // For cross-midnight sleeps, show a time range and sort by wake time
            // (or start of selected day) so it appears at the correct position.
            let sortDate: Date
            let timeLabel: String
            if startIsOnDifferentDay {
                // Sort by the later of endTime or start-of-day so the entry
                // sits chronologically among today's events.
                sortDate = r.endTime ?? max(st, selectedDayStart)
                // Show "10:00 PM – 6:00 AM" range with overnight indicator
                let startStr = st.formatted(date: .omitted, time: .shortened)
                let endStr = (r.endTime ?? Date()).formatted(date: .omitted, time: .shortened)
                timeLabel = "\(startStr) – \(endStr)"
            } else {
                sortDate = st
                timeLabel = st.formatted(date: .omitted, time: .shortened)
            }
            let titleSuffix = startIsOnDifferentDay && !isOngoing
                ? " 🌙"  // overnight indicator
                : ""
            let baseTitle: String
            if isOngoing {
                baseTitle = "\(NSLocalizedString("home.sleep", comment: "")) (\(NSLocalizedString("home.inProgress", comment: "").lowercased()))"
            } else {
                baseTitle = NSLocalizedString("home.sleep", comment: "")
            }
            items.append(ActivityItem(
                id: "s-\(r.id?.uuidString ?? r.objectID.uriRepresentation().lastPathComponent)",
                date: sortDate,
                icon: isOngoing ? "moon.fill" : "moon.zzz.fill",
                color: .blSleep,
                title: baseTitle + titleSuffix,
                detail: detail,
                timeLabel: timeLabel,
                notes: r.notes,
                record: .sleep(r)
            ))
        }

        for r in todayDiapers {
            guard let ts = r.timestamp else { continue }
            let dt = DiaperType(rawValue: r.diaperType ?? "")
            let diaperDetail: String = {
                guard let dt = dt else { return "" }
                return "\(dt.icon) \(dt.displayName)"
            }()
            items.append(ActivityItem(
                id: "d-\(r.id?.uuidString ?? r.objectID.uriRepresentation().lastPathComponent)",
                date: ts,
                icon: "oval.fill",
                color: .blDiaper,
                title: NSLocalizedString("home.diaper", comment: ""),
                detail: diaperDetail,
                timeLabel: ts.formatted(date: .omitted, time: .shortened),
                notes: r.notes,
                record: .diaper(r)
            ))
        }

        for r in todayGrowth {
            guard let d = r.date else { continue }
            let unit = appState.measurementUnit
            let detail: String = {
                var parts: [String] = []
                if r.weightKG > 0 {
                    parts.append(String(format: "⚖️ %.2f %@", unit.weightFromKG(r.weightKG), unit.weightLabel))
                }
                if r.heightCM > 0 {
                    parts.append(String(format: "📏 %.1f %@", unit.lengthFromCM(r.heightCM), unit.heightLabel))
                }
                if r.headCircumferenceCM > 0 {
                    parts.append(String(format: "🔵 %.1f %@", unit.lengthFromCM(r.headCircumferenceCM), unit.heightLabel))
                }
                return parts.joined(separator: " · ")
            }()
            items.append(ActivityItem(
                id: "g-\(r.id?.uuidString ?? r.objectID.uriRepresentation().lastPathComponent)",
                date: d,
                icon: "chart.line.uptrend.xyaxis",
                color: .blGrowth,
                title: NSLocalizedString("home.growth", comment: ""),
                detail: detail,
                timeLabel: d.formatted(date: .omitted, time: .shortened),
                notes: r.notes,
                record: .growth(r)
            ))
        }

        // Newest first
        return items.sorted { $0.date > $1.date }
    }

    private var recentActivitySection: some View {
        let items = timelineItems
        let previewLimit = 20
        let displayItems = isTimelineExpanded ? items : Array(items.prefix(previewLimit))
        let hasMore = items.count > previewLimit

        return VStack(spacing: 12) {
            HStack {
                BLSectionHeader(title: isSelectedDateToday ? NSLocalizedString("home.todaysTimeline", comment: "") : NSLocalizedString("home.dayTimeline", comment: ""))
                Spacer()
                if items.count > 0 {
                    Text(String(format: NSLocalizedString("home.events %lld", comment: ""), items.count))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.blTextTertiary)
                }
            }
            .padding(.horizontal, 20)

            VStack(spacing: 1) {
                ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                    let timeAgo: String = {
                        if isSelectedDateToday {
                            // For sleep that's ongoing, show "Now"
                            if item.detail.contains(NSLocalizedString("home.ongoing", comment: "")) { return NSLocalizedString("home.now", comment: "") }
                            return Self.timeAgoText(from: item.date)
                        }
                        return item.timeLabel
                    }()

                    TimeSinceRow(
                        icon: item.icon,
                        color: item.color,
                        title: item.title,
                        detail: item.detail,
                        timeAgo: timeAgo,
                        timeLabel: item.timeLabel,
                        notes: item.notes,
                        showTimeAgoHighlight: isSelectedDateToday
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        switch item.record {
                        case .feeding(let r): feedingToEdit = r
                        case .sleep(let r):   sleepToEdit = r
                        case .diaper(let r):  diaperToEdit = r
                        case .growth(let r):  growthToEdit = r
                        }
                    }
                    .contextMenu {
                        Button {
                            switch item.record {
                            case .feeding(let r): feedingToEdit = r
                            case .sleep(let r):   sleepToEdit = r
                            case .diaper(let r):  diaperToEdit = r
                            case .growth(let r):  growthToEdit = r
                            }
                        } label: {
                            Label(NSLocalizedString("home.edit", comment: ""), systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            switch item.record {
                            case .feeding(let r): timelineRecordToDelete = r
                            case .sleep(let r):   timelineRecordToDelete = r
                            case .diaper(let r):  timelineRecordToDelete = r
                            case .growth(let r):  timelineRecordToDelete = r
                            }
                        } label: {
                            Label(NSLocalizedString("home.delete", comment: ""), systemImage: "trash")
                        }
                    }

                    if index < displayItems.count - 1 {
                        Divider().padding(.leading, 70)
                    }
                }
            }
            .blCard()
            .padding(.horizontal, 20)

            if hasMore {
                Button {
                    Haptic.selection()
                    withAnimation(.spring(response: 0.35)) {
                        isTimelineExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(isTimelineExpanded
                             ? NSLocalizedString("home.showLess", comment: "")
                             : String(format: NSLocalizedString("home.showAllEvents %lld", comment: ""), items.count))
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: isTimelineExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.blPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Time Since Row
struct TimeSinceRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let timeAgo: String
    let timeLabel: String
    var notes: String?
    /// When true (today), timeAgo is shown in the accent color as a prominent badge.
    /// When false (past date), timeAgo is shown in a subdued style since relative
    /// "time ago" is not meaningful — it just mirrors the time for quick scanning.
    var showTimeAgoHighlight: Bool = true

    /// Cleaned notes — nil if empty or whitespace-only
    private var displayNotes: String? {
        guard let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var accessibilityText: String {
        var parts = [title]
        if !detail.isEmpty { parts.append(detail) }
        parts.append(String(format: NSLocalizedString("a11y.at %@", comment: ""), timeLabel))
        if showTimeAgoHighlight && !timeAgo.isEmpty { parts.append(timeAgo) }
        if let displayNotes { parts.append(String(format: NSLocalizedString("a11y.note %@", comment: ""), displayNotes)) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.blTextPrimary)
                    if !detail.isEmpty {
                        Text("·")
                            .font(.system(size: 13))
                            .foregroundColor(.blTextTertiary)
                        Text(detail)
                            .font(.system(size: 14))
                            .foregroundColor(color)
                    }
                }
                Text(timeLabel)
                    .font(.system(size: 13))
                    .foregroundColor(.blTextSecondary)

                // Show notes inline if present
                if let displayNotes {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blTextTertiary)
                        Text(displayNotes)
                            .font(.system(size: 12))
                            .foregroundColor(.blTextTertiary)
                            .lineLimit(1)
                    }
                    .padding(.top, 1)
                }
            }
            Spacer()
            Text(timeAgo)
                .font(.system(size: 14, weight: showTimeAgoHighlight ? .semibold : .medium))
                .foregroundColor(showTimeAgoHighlight ? color : .blTextSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(NSLocalizedString("a11y.longPressEditDelete", comment: ""))
    }
}
