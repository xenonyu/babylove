import SwiftUI
import CoreData

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
    @State private var selectedDate: Date = Date()
    /// Tracks the calendar day when the view was last active, so we can detect day-boundary crossings
    @State private var lastActiveCalendarDay: Date = Calendar.current.startOfDay(for: Date())
    /// Set of start-of-day dates that have at least one record (within the date range window)
    @State private var activeDays: Set<Date> = []

    // Global "last event" times — not filtered by selected day
    @State private var globalLastFeedingTime: Date?
    @State private var globalLastFeedingIsOngoing: Bool = false
    @State private var globalLastSleepEnd: Date?
    @State private var globalLastSleepIsOngoing: Bool = false
    @State private var globalLastDiaperTime: Date?

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
            Calendar.current.date(byAdding: .day, value: 1,
                                  to: Calendar.current.startOfDay(for: Date()))! as NSDate,
            Calendar.current.startOfDay(for: Date()) as NSDate
        )
    )
    private var todaySleeps: FetchedResults<CDSleepRecord>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.timestamp, order: .reverse)],
        predicate: NSPredicate(format: "timestamp >= %@", Calendar.current.startOfDay(for: Date()) as NSDate)
    )
    private var todayDiapers: FetchedResults<CDDiaperRecord>

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
                               Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: Date()))! as NSDate)
    )
    private var weekFeedings: FetchedResults<CDFeedingRecord>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.startTime, order: .reverse)],
        predicate: NSPredicate(format: "startTime >= %@",
                               Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: Date()))! as NSDate)
    )
    private var weekSleeps: FetchedResults<CDSleepRecord>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.timestamp, order: .reverse)],
        predicate: NSPredicate(format: "timestamp >= %@",
                               Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: Date()))! as NSDate)
    )
    private var weekDiapers: FetchedResults<CDDiaperRecord>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.timestamp, order: .reverse)],
        predicate: NSPredicate(format: "timestamp >= %@ AND timestamp < %@",
                               Calendar.current.date(byAdding: .day, value: -14, to: Calendar.current.startOfDay(for: Date()))! as NSDate,
                               Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: Date()))! as NSDate)
    )
    private var prevWeekFeedings: FetchedResults<CDFeedingRecord>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.startTime, order: .reverse)],
        predicate: NSPredicate(format: "startTime >= %@ AND startTime < %@",
                               Calendar.current.date(byAdding: .day, value: -14, to: Calendar.current.startOfDay(for: Date()))! as NSDate,
                               Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: Date()))! as NSDate)
    )
    private var prevWeekSleeps: FetchedResults<CDSleepRecord>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.timestamp, order: .reverse)],
        predicate: NSPredicate(format: "timestamp >= %@ AND timestamp < %@",
                               Calendar.current.date(byAdding: .day, value: -14, to: Calendar.current.startOfDay(for: Date()))! as NSDate,
                               Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: Date()))! as NSDate)
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
        let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: selectedDate))! as NSDate
        todayFeedings.nsPredicate = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", startOfDay, endOfDay)
        // Overlap predicate: include sleeps that started before the day ends
        // AND (ended after the day starts OR are still ongoing).
        todaySleeps.nsPredicate   = NSPredicate(format: "startTime < %@ AND (endTime >= %@ OR endTime == nil)", endOfDay, startOfDay)
        todayDiapers.nsPredicate  = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", startOfDay, endOfDay)
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

        // Current week (last 7 days)
        weekFeedings.nsPredicate = NSPredicate(format: "timestamp >= %@", weekStartNS)
        weekSleeps.nsPredicate   = NSPredicate(format: "startTime >= %@", weekStartNS)
        weekDiapers.nsPredicate  = NSPredicate(format: "timestamp >= %@", weekStartNS)

        // Previous week (days -14 to -7)
        prevWeekFeedings.nsPredicate = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", prevWeekStartNS, weekStartNS)
        prevWeekSleeps.nsPredicate   = NSPredicate(format: "startTime >= %@ AND startTime < %@", prevWeekStartNS, weekStartNS)
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
            let h = totalBreastMinutes / 60
            let m = totalBreastMinutes % 60
            parts.append(h > 0 ? "\(h)h \(m)m" : "\(m) min")
        }
        // Last breast side (helps moms remember which side to use next)
        if let lastSide = lastBreastSide {
            parts.append("Last: \(lastSide.displayName)")
        }
        return parts.joined(separator: " · ")
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
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        let remMins = minutes % 60
        if hours < 24 {
            return remMins > 0 ? "\(hours)h \(remMins)m ago" : "\(hours)h ago"
        }
        let days = hours / 24
        return days == 1 ? "1d ago" : "\(days)d ago"
    }

    /// Time since last feeding (global — not limited to selected day), or "feeding now" if ongoing
    private var feedingTimeSince: String {
        if globalLastFeedingIsOngoing { return "feeding now" }
        return Self.timeSinceText(from: globalLastFeedingTime)
    }

    /// Time since last sleep ended (global), or "sleeping now" if ongoing
    private var sleepTimeSince: String {
        if globalLastSleepIsOngoing { return "sleeping now" }
        return Self.timeSinceText(from: globalLastSleepEnd)
    }

    /// Time since last diaper change (global)
    private var diaperTimeSince: String {
        Self.timeSinceText(from: globalLastDiaperTime)
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

    // MARK: - Quick Log Hints

    /// Contextual hint for the Feeding quick log card
    private var quickLogFeedingHint: String? {
        if globalLastFeedingIsOngoing { return "In progress" }
        // Show "Next: Right/Left" if we know the last breast side
        if let lastSide = lastBreastSide, lastSide != .both {
            let nextSide = lastSide == .left ? "Right" : "Left"
            return "Next: \(nextSide)"
        }
        // Otherwise show time since last feeding
        guard let lastTime = globalLastFeedingTime else { return nil }
        return Self.timeSinceText(from: lastTime)
    }

    /// Contextual hint for the Sleep quick log card
    private var quickLogSleepHint: String? {
        if globalLastSleepIsOngoing { return "Sleeping now" }
        guard let lastTime = globalLastSleepEnd else { return nil }
        return Self.timeSinceText(from: lastTime)
    }

    /// Contextual hint for the Diaper quick log card
    private var quickLogDiaperHint: String? {
        guard let lastTime = globalLastDiaperTime else { return nil }
        return Self.timeSinceText(from: lastTime)
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
        let h = totalSleepMinutes / 60
        let m = totalSleepMinutes % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    /// Subtitle for the sleep stat badge: nap count + longest nap info
    private var sleepSubtitle: String {
        let count = todaySleeps.count
        guard count > 0 else { return "" }
        var parts: [String] = []
        // Nap/session count
        parts.append(count == 1 ? "1 nap" : "\(count) naps")
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
                let h = longestMinutes / 60
                let m = longestMinutes % 60
                let longestText = h > 0 ? "\(h)h \(m)m" : "\(m)m"
                parts.append("longest \(longestText)")
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
                            BLSectionHeader(title: isSelectedDateToday ? "Today's Summary" : "Day Summary")
                                .padding(.horizontal, 20)

                            HStack(spacing: 12) {
                                StatBadge(value: "\(todayFeedings.count)",
                                          label: "Feedings",
                                          color: .blFeeding,
                                          subtitle: feedingVolumeSubtitle,
                                          timeSince: isSelectedDateToday ? feedingTimeSince : nil)
                                StatBadge(value: sleepText,
                                          label: "Sleep",
                                          color: .blSleep,
                                          subtitle: sleepSubtitle,
                                          timeSince: isSelectedDateToday ? sleepTimeSince : nil)
                                StatBadge(value: "\(todayDiapers.count)",
                                          label: "Diapers",
                                          color: .blDiaper,
                                          subtitle: diaperBreakdownSubtitle,
                                          timeSince: isSelectedDateToday ? diaperTimeSince : nil)
                            }
                            .padding(.horizontal, 20)
                        }

                        // Quick log — available for all dates (retroactive logging)
                        VStack(spacing: 12) {
                            BLSectionHeader(title: isSelectedDateToday ? "Quick Log" : "Add Record")
                                .padding(.horizontal, 20)

                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 12) {
                                QuickLogCard(icon: "drop.fill",
                                             label: "Feeding",
                                             color: .blFeeding,
                                             hint: isSelectedDateToday ? quickLogFeedingHint : nil) { showFeedingLog = true }
                                QuickLogCard(icon: "moon.zzz.fill",
                                             label: "Sleep",
                                             color: .blSleep,
                                             hint: isSelectedDateToday ? quickLogSleepHint : nil) { showSleepLog = true }
                                QuickLogCard(icon: "oval.fill",
                                             label: "Diaper",
                                             color: .blDiaper,
                                             hint: isSelectedDateToday ? quickLogDiaperHint : nil) { showDiaperLog = true }
                                QuickLogCard(icon: "chart.bar.fill",
                                             label: "Growth",
                                             color: .blGrowth) { showGrowthLog = true }
                            }
                            .padding(.horizontal, 20)
                        }

                        // Weekly summary (only on today view, only if there's any data)
                        if isSelectedDateToday && (!weekFeedings.isEmpty || !weekSleeps.isEmpty || !weekDiapers.isEmpty) {
                            weeklySummaryCard
                        }

                        // Recent activity or empty state
                        if !todayFeedings.isEmpty || !todaySleeps.isEmpty || !todayDiapers.isEmpty {
                            recentActivitySection
                        } else {
                            emptyDaySection
                        }

                        Spacer(minLength: 100)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                updatePredicates()
                updateWeeklyPredicates()
                refreshGlobalLastTimes()
                refreshActiveDays()
                startSleepTimerIfNeeded()
                startFeedingTimerIfNeeded()
            }
            .onDisappear {
                stopSleepTimer()
                stopFeedingTimer()
            }
            .onChange(of: selectedDate) { _, _ in
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
                } else if phase == .background {
                    stopSleepTimer()
                    stopFeedingTimer()
                }
            }
            .onChange(of: todayFeedings.count) { _, _ in refreshGlobalLastTimes(); refreshActiveDays() }
            .onChange(of: todaySleeps.count) { _, _ in refreshGlobalLastTimes(); refreshActiveDays() }
            .onChange(of: todayDiapers.count) { _, _ in refreshGlobalLastTimes(); refreshActiveDays() }
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
        // Timeline delete confirmation
        .alert("Delete Record?", isPresented: Binding(
            get: { timelineRecordToDelete != nil },
            set: { if !$0 { timelineRecordToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { timelineRecordToDelete = nil }
            Button("Delete", role: .destructive) {
                Haptic.warning()
                if let record = timelineRecordToDelete {
                    // Determine record type for a contextual toast message
                    let (msg, icon, color): (String, String, Color) = {
                        if record is CDFeedingRecord {
                            return ("Feeding deleted", "trash.fill", Color.blFeeding)
                        } else if record is CDSleepRecord {
                            return ("Sleep deleted", "trash.fill", Color.blSleep)
                        } else if record is CDDiaperRecord {
                            return ("Diaper deleted", "trash.fill", Color.blDiaper)
                        }
                        return ("Record deleted", "trash.fill", Color.blPrimary)
                    }()
                    withAnimation { vm.deleteObject(record, in: ctx) }
                    appState.showToast(msg, icon: icon, color: color)
                }
                timelineRecordToDelete = nil
            }
        } message: {
            Text("This record will be permanently removed.")
        }
        // End sleep timer confirmation
        .alert("End Sleep?", isPresented: $showEndSleepConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("End Sleep") {
                endOngoingSleep()
            }
        } message: {
            Text("Record \(elapsedText) of sleep for \(appState.currentBaby?.name ?? "baby")?")
        }
        // End feeding timer confirmation
        .alert("End Feeding?", isPresented: $showEndFeedingConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("End Feeding") {
                endOngoingFeeding()
            }
        } message: {
            let feedType = FeedType(rawValue: ongoingFeeding?.feedType ?? "")?.displayName ?? "Feeding"
            Text("Record \(feedingElapsedText) of \(feedType.lowercased()) for \(appState.currentBaby?.name ?? "baby")?")
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
            globalLastFeedingTime = lastFeeding.timestamp
            // An ongoing breast/pump feeding has durationMinutes == 0
            let ft = FeedType(rawValue: lastFeeding.feedType ?? "")
            let isTimerType = ft == .breast || ft == .pump
            globalLastFeedingIsOngoing = isTimerType && lastFeeding.durationMinutes == 0
        } else {
            globalLastFeedingTime = nil
            globalLastFeedingIsOngoing = false
        }

        // Last sleep (any day)
        let sleepReq: NSFetchRequest<CDSleepRecord> = CDSleepRecord.fetchRequest()
        sleepReq.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: false)]
        sleepReq.fetchLimit = 1
        if let lastSleep = (try? ctx.fetch(sleepReq))?.first {
            if lastSleep.endTime == nil {
                globalLastSleepEnd = lastSleep.startTime
                globalLastSleepIsOngoing = true
            } else {
                globalLastSleepEnd = lastSleep.endTime
                globalLastSleepIsOngoing = false
            }
        } else {
            globalLastSleepEnd = nil
            globalLastSleepIsOngoing = false
        }

        // Last diaper (any day)
        let diaperReq: NSFetchRequest<CDDiaperRecord> = CDDiaperRecord.fetchRequest()
        diaperReq.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        diaperReq.fetchLimit = 1
        globalLastDiaperTime = (try? ctx.fetch(diaperReq))?.first?.timestamp
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

        // Sleep start times
        let sleepReq: NSFetchRequest<CDSleepRecord> = CDSleepRecord.fetchRequest()
        sleepReq.predicate = NSPredicate(format: "startTime >= %@", rangeStartNS)
        sleepReq.propertiesToFetch = ["startTime"]
        if let results = try? ctx.fetch(sleepReq) {
            for r in results {
                if let st = r.startTime { days.insert(cal.startOfDay(for: st)) }
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
        var ok = false
        withAnimation(.spring(response: 0.4)) {
            ok = vm.endSleepByID(id, context: ctx)
        }
        if ok {
            Haptic.success()
            stopSleepTimer()
            appState.showToast("Sleep ended", icon: "sun.and.horizon.fill", color: .blSleep)
        } else {
            Haptic.error()
            appState.showToast("Save failed — try again", icon: "exclamationmark.triangle.fill", color: .red)
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
                    Text("Baby is sleeping")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.blTextPrimary)
                    if let start = record.startTime {
                        Text("Since \(start.formatted(date: .omitted, time: .shortened))")
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
                    Text("End Sleep")
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
        .accessibilityLabel("Baby is sleeping, elapsed \(elapsedText)")
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
        var ok = false
        withAnimation(.spring(response: 0.4)) {
            ok = vm.endFeedingByID(id, context: ctx)
        }
        if ok {
            Haptic.success()
            stopFeedingTimer()
            appState.showToast("Feeding ended", icon: "checkmark.circle.fill", color: .blFeeding)
        } else {
            Haptic.error()
            appState.showToast("Save failed — try again", icon: "exclamationmark.triangle.fill", color: .red)
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
                    Text("Feeding in progress")
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
                    Text("End Feeding")
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
        .accessibilityLabel("Feeding in progress, elapsed \(feedingElapsedText)")
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

    private var dateNavigationBar: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    let cal = Calendar.current
                    if let prev = cal.date(byAdding: .day, value: -1, to: selectedDate),
                       cal.startOfDay(for: prev) >= earliestNavigableDate {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedDate = prev }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(canNavigateBack ? .blPrimary : .blTextTertiary)
                        .frame(width: 32, height: 32)
                }
                .disabled(!canNavigateBack)

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
                        let cal = Calendar.current
                        let tomorrow = cal.date(byAdding: .day, value: 1, to: selectedDate) ?? Date()
                        let capped = min(tomorrow, Date())
                        withAnimation(.easeInOut(duration: 0.2)) { selectedDate = capped }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.blPrimary)
                            .frame(width: 32, height: 32)
                    }
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
                            .accessibilityLabel("\(isToday ? dateHeaderText : "\(dayOfWeekText(date)) \(dayNumberText(date))")\(hasActivity ? ", has activity" : "")")
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
                        Text("Back to Today")
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
        let weekStart = cal.date(byAdding: .day, value: -7, to: today)!
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
        let prevWeekStart = cal.date(byAdding: .day, value: -14, to: today)!
        let prevWeekEnd = cal.date(byAdding: .day, value: -7, to: today)!
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

    /// Average sleep hours per day this week
    /// Note: Ongoing sessions (endTime == nil) are skipped so the running
    /// timer doesn't inflate the weekly average — consistent with prevWeek.
    private var weekAvgSleepHours: Double {
        guard !weekSleeps.isEmpty else { return 0 }
        let completedSleeps = weekSleeps.filter { $0.endTime != nil }
        guard !completedSleeps.isEmpty else { return 0 }
        let totalMinutes = completedSleeps.reduce(0) { sum, r in
            guard let s = r.startTime, let e = r.endTime else { return sum }
            return sum + Int(e.timeIntervalSince(s) / 60)
        }
        return Double(totalMinutes) / 60.0 / currentWeekActiveDays
    }

    /// Average diapers per day this week
    private var weekAvgDiapers: Double {
        guard !weekDiapers.isEmpty else { return 0 }
        return Double(weekDiapers.count) / currentWeekActiveDays
    }

    /// Average feedings per day previous week
    private var prevWeekAvgFeedings: Double {
        guard !prevWeekFeedings.isEmpty else { return 0 }
        return Double(prevWeekFeedings.count) / prevWeekActiveDays
    }

    /// Average sleep hours per day previous week
    /// Note: Ongoing sessions (endTime == nil) are skipped because historical
    /// averages must not use the current time as a stand-in end time.
    private var prevWeekAvgSleepHours: Double {
        guard !prevWeekSleeps.isEmpty else { return 0 }
        let totalMinutes = prevWeekSleeps.reduce(0) { sum, r in
            guard let s = r.startTime, let e = r.endTime else { return sum }
            return sum + Int(e.timeIntervalSince(s) / 60)
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
            return "Last \(days) Day\(days == 1 ? "" : "s")"
        }
        return "This Week"
    }

    private var weeklySummaryCard: some View {
        VStack(spacing: 12) {
            BLSectionHeader(title: weeklySummaryTitle)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                // Row 1: Feedings
                if !weekFeedings.isEmpty {
                    weeklyRow(
                        icon: "drop.fill",
                        color: .blFeeding,
                        title: "Feedings",
                        value: String(format: "%.1f", weekAvgFeedings),
                        unit: "/day",
                        total: "\(weekFeedings.count) total",
                        current: weekAvgFeedings,
                        previous: prevWeekAvgFeedings
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
                        title: "Sleep",
                        value: String(format: "%.1fh", weekAvgSleepHours),
                        unit: "/day",
                        total: "\(weekSleeps.count) naps",
                        current: weekAvgSleepHours,
                        previous: prevWeekAvgSleepHours
                    )
                }

                if (!weekFeedings.isEmpty || !weekSleeps.isEmpty) && !weekDiapers.isEmpty {
                    Divider().padding(.leading, 60)
                }

                // Row 3: Diapers
                if !weekDiapers.isEmpty {
                    weeklyRow(
                        icon: "oval.fill",
                        color: .blDiaper,
                        title: "Diapers",
                        value: String(format: "%.1f", weekAvgDiapers),
                        unit: "/day",
                        total: "\(weekDiapers.count) total",
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
                Text(baby?.ageText ?? "")
                    .font(.system(size: 15))
                    .foregroundColor(.blTextSecondary)
                Text(Date().formatted(date: .complete, time: .omitted))
                    .font(.system(size: 12))
                    .foregroundColor(.blTextTertiary)
            }

            Spacer()
        }
        .padding(20)
        .blCard()
        .padding(.horizontal, 20)
    }

    // MARK: - Empty Day State

    private var emptyDaySection: some View {
        VStack(spacing: 16) {
            BLSectionHeader(title: "Recent Activity")
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

                Text(isSelectedDateToday ? "No activity yet today" : "No activity on this day")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blTextSecondary)

                Text(isSelectedDateToday
                     ? "Tap a Quick Log button above to start tracking \(baby?.name ?? "baby")'s day"
                     : "No records were logged for \(baby?.name ?? "baby") on this date")
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
        if seconds < 60 { return "Just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        let remainMinutes = minutes % 60
        if hours < 24 {
            return remainMinutes > 0 ? "\(hours)h \(remainMinutes)m ago" : "\(hours)h ago"
        }
        let days = hours / 24
        if days == 1 {
            return BLDateFormatters.relativeShort.string(from: Date(timeIntervalSinceNow: -86400))
        }
        return "\(days)d ago"
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
            parts.append("Ongoing")
        } else if r.durationMinutes > 0 {
            parts.append("\(r.durationMinutes)m")
        }
        if r.amountML > 0 {
            let display = unit.volumeFromML(r.amountML)
            if unit == .metric {
                parts.append("\(Int(display)) ml")
            } else {
                parts.append(String(format: "%.1f oz", display))
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
    @State private var timelineRecordToDelete: NSManagedObject?

    /// A unified activity item for the chronological timeline.
    private struct ActivityItem: Identifiable {
        enum RecordRef {
            case feeding(CDFeedingRecord)
            case sleep(CDSleepRecord)
            case diaper(CDDiaperRecord)
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
                ? "\(ft?.displayName ?? "Feeding") (in progress)"
                : (ft?.displayName ?? "Feeding")
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
            let detail: String = {
                var parts: [String] = []
                // Location
                if let loc = r.location, !loc.isEmpty,
                   let sl = SleepLocation(rawValue: loc) {
                    parts.append(sl.displayName)
                }
                // Duration or Ongoing
                if r.endTime == nil {
                    parts.append("Ongoing")
                } else if let e = r.endTime {
                    let mins = Int(e.timeIntervalSince(st) / 60)
                    let h = mins / 60, m = mins % 60
                    parts.append(h > 0 ? "\(h)h \(m)m" : "\(m)m")
                }
                return parts.joined(separator: " · ")
            }()
            let isOngoing = r.endTime == nil
            items.append(ActivityItem(
                id: "s-\(r.id?.uuidString ?? r.objectID.uriRepresentation().lastPathComponent)",
                date: st,
                icon: isOngoing ? "moon.fill" : "moon.zzz.fill",
                color: .blSleep,
                title: isOngoing ? "Sleep (in progress)" : "Sleep",
                detail: detail,
                timeLabel: st.formatted(date: .omitted, time: .shortened),
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
                title: "Diaper",
                detail: diaperDetail,
                timeLabel: ts.formatted(date: .omitted, time: .shortened),
                notes: r.notes,
                record: .diaper(r)
            ))
        }

        // Newest first
        return items.sorted { $0.date > $1.date }
    }

    private var recentActivitySection: some View {
        let items = timelineItems
        let displayItems = Array(items.prefix(20))

        return VStack(spacing: 12) {
            HStack {
                BLSectionHeader(title: isSelectedDateToday ? "Today's Timeline" : "Day Timeline")
                Spacer()
                if items.count > 0 {
                    Text("\(items.count) events")
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
                            if item.detail.contains("Ongoing") { return "Now" }
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
                        }
                    }
                    .contextMenu {
                        Button {
                            switch item.record {
                            case .feeding(let r): feedingToEdit = r
                            case .sleep(let r):   sleepToEdit = r
                            case .diaper(let r):  diaperToEdit = r
                            }
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            switch item.record {
                            case .feeding(let r): timelineRecordToDelete = r
                            case .sleep(let r):   timelineRecordToDelete = r
                            case .diaper(let r):  timelineRecordToDelete = r
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                    if index < displayItems.count - 1 {
                        Divider().padding(.leading, 70)
                    }
                }
            }
            .blCard()
            .padding(.horizontal, 20)

            if items.count > 20 {
                Text("Showing latest 20 of \(items.count) events")
                    .font(.system(size: 12))
                    .foregroundColor(.blTextTertiary)
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
        parts.append("at \(timeLabel)")
        if showTimeAgoHighlight && !timeAgo.isEmpty { parts.append(timeAgo) }
        if let displayNotes { parts.append("note: \(displayNotes)") }
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
        .accessibilityHint("Long press to edit or delete")
    }
}
