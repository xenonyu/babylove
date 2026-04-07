import SwiftUI
import CoreData

private let _trackToday = Calendar.current.startOfDay(for: Date())
private func _trackSafeAdd(_ component: Calendar.Component, value: Int, to date: Date) -> Date {
    Calendar.current.date(byAdding: component, value: value, to: date) ?? date
}

struct TrackView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) var ctx
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var vm: TrackViewModel = TrackViewModel(context: PersistenceController.shared.container.viewContext)

    @State private var showFeedingLog  = false
    @State private var showSleepLog    = false
    @State private var showDiaperLog   = false
    @State private var showGrowthLog   = false
    @State private var recordToDelete: NSManagedObject?
    /// Tracks the calendar day when predicates were last refreshed, so we can
    /// detect midnight crossings and update the 14-day fetch windows.
    @State private var lastRefreshedDay: Date = Calendar.current.startOfDay(for: Date())

    // Edit states
    @State private var feedingToEdit: CDFeedingRecord?
    @State private var sleepToEdit: CDSleepRecord?
    @State private var diaperToEdit: CDDiaperRecord?
    @State private var growthToEdit: CDGrowthRecord?

    // Total record counts (for "See All (N)" badges)
    @State private var totalFeedingCount: Int = 0
    @State private var totalSleepCount: Int = 0
    @State private var totalDiaperCount: Int = 0
    @State private var totalGrowthCount: Int = 0

    /// Tick updated every 60s so "time since" hints stay fresh
    @State private var minuteTick: Date = Date()
    /// Timer that fires every 60s to update minuteTick
    @State private var minuteTimer: Timer?

    // Limit high-frequency records to the last 14 days to avoid loading thousands
    // of objects into memory. Only 5 are shown per section; the "See All" views
    // have their own unbounded FetchRequests.
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.timestamp, order: .reverse)],
        predicate: NSPredicate(format: "timestamp >= %@",
                               _trackSafeAdd(.day, value: -14, to: _trackToday) as NSDate)
    ) private var recentFeedings: FetchedResults<CDFeedingRecord>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.startTime, order: .reverse)],
        predicate: NSPredicate(format: "startTime >= %@",
                               _trackSafeAdd(.day, value: -14, to: _trackToday) as NSDate)
    ) private var recentSleeps: FetchedResults<CDSleepRecord>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.timestamp, order: .reverse)],
        predicate: NSPredicate(format: "timestamp >= %@",
                               _trackSafeAdd(.day, value: -14, to: _trackToday) as NSDate)
    ) private var recentDiapers: FetchedResults<CDDiaperRecord>

    // Growth records are infrequent (monthly), so keep unbounded
    @FetchRequest(
        entity: CDGrowthRecord.entity(),
        sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
    ) private var recentGrowth: FetchedResults<CDGrowthRecord>

    // MARK: - Quick Log Hints (time since last)

    /// Short "time since" string, e.g. "32m ago", "1h 5m ago", "2d ago"
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

    /// Contextual hint for the Feeding quick log card.
    private var feedingHint: String? {
        _ = minuteTick
        guard let record = recentFeedings.first else { return nil }
        let isOngoing = Self.isFeedingOngoing(record)
        if isOngoing { return NSLocalizedString("home.inProgress", comment: "") }
        // "Next: Right/Left" if last breast side is known
        let ft = FeedType(rawValue: record.feedType ?? "")
        if (ft == .breast || ft == .pump),
           let sideRaw = record.breastSide, !sideRaw.isEmpty,
           let side = BreastSide(rawValue: sideRaw), side != .both {
            let nextSide = side == .left ? BreastSide.right.displayName : BreastSide.left.displayName
            return String(format: NSLocalizedString("home.next %@", comment: ""), nextSide)
        }
        guard let ts = record.timestamp else { return nil }
        let timeSince = Self.timeSinceText(from: ts)
        if let ft { return "\(ft.displayName) · \(timeSince)" }
        return timeSince
    }

    /// Contextual hint for the Sleep quick log card.
    private var sleepHint: String? {
        _ = minuteTick
        guard let record = recentSleeps.first else { return nil }
        let isOngoing = record.endTime == nil
        if isOngoing {
            if let loc = record.location, let sl = SleepLocation(rawValue: loc) {
                return "\(sl.displayName) · \(NSLocalizedString("home.sleepingNow", comment: ""))"
            }
            return NSLocalizedString("home.sleepingNow", comment: "")
        }
        guard let endTime = record.endTime else { return nil }
        let timeSince = Self.timeSinceText(from: endTime)
        if let loc = record.location, let sl = SleepLocation(rawValue: loc) {
            return "\(sl.displayName) · \(timeSince)"
        }
        return timeSince
    }

    /// Contextual hint for the Diaper quick log card.
    private var diaperHint: String? {
        _ = minuteTick
        guard let record = recentDiapers.first, let ts = record.timestamp else { return nil }
        let timeSince = Self.timeSinceText(from: ts)
        if let dtype = DiaperType(rawValue: record.diaperType ?? "") {
            return "\(dtype.icon) \(dtype.displayName) · \(timeSince)"
        }
        return timeSince
    }

    /// Contextual hint for the Growth quick log card.
    private var growthHint: String? {
        guard let record = recentGrowth.first, let lastDate = record.date else { return nil }
        let timeSince = Self.timeSinceText(from: lastDate)
        let unit = appState.measurementUnit
        let valueStr: String? = if record.weightKG > 0 {
            String(format: "%.1f %@", unit.weightFromKG(record.weightKG), unit.weightLabel)
        } else if record.heightCM > 0 {
            String(format: "%.1f %@", unit.lengthFromCM(record.heightCM), unit.heightLabel)
        } else if record.headCircumferenceCM > 0 {
            String(format: "%.1f %@", unit.lengthFromCM(record.headCircumferenceCM), unit.heightLabel)
        } else {
            nil
        }
        if let valueStr { return "\(valueStr) · \(timeSince)" }
        return timeSince
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Quick log grid
                        VStack(spacing: 12) {
                            BLSectionHeader(title: String(localized: "track.logActivity"))
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 12) {
                                QuickLogCard(icon: "drop.fill",
                                             label: String(localized: "track.feeding"),
                                             color: .blFeeding,
                                             hint: feedingHint,
                                             isActive: isFeedingActive) { showFeedingLog = true }
                                QuickLogCard(icon: "moon.zzz.fill",
                                             label: String(localized: "track.sleep"),
                                             color: .blSleep,
                                             hint: sleepHint,
                                             isActive: isSleepActive) { showSleepLog = true }
                                QuickLogCard(icon: "oval.fill",
                                             label: String(localized: "track.diaper"),
                                             color: .blDiaper,
                                             hint: diaperHint) { showDiaperLog = true }
                                QuickLogCard(icon: "chart.bar.fill",
                                             label: String(localized: "track.growth"),
                                             color: .blGrowth,
                                             hint: growthHint) { showGrowthLog = true }
                            }
                        }
                        .padding(.horizontal, 20)

                        // Empty state when no records exist yet
                        if recentFeedings.isEmpty && recentSleeps.isEmpty && recentDiapers.isEmpty && recentGrowth.isEmpty {
                            VStack(spacing: 16) {
                                Spacer().frame(height: 20)
                                Image(systemName: "heart.text.clipboard")
                                    .font(.system(size: 48))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.blPrimary, .blTeal],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                Text(String(localized: "track.noRecordsYet"))
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.blTextPrimary)
                                Text(String(localized: "track.tapToStart"))
                                    .font(.system(size: 15))
                                    .foregroundColor(.blTextSecondary)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(3)
                                Spacer().frame(height: 8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }

                        // Recent feedings
                        if !recentFeedings.isEmpty {
                            let feedingItems = Array(recentFeedings.prefix(5))
                            recentSection(title: String(localized: "track.feedings"), color: .blFeeding, totalCount: totalFeedingCount, destination: AllFeedingsView()) {
                                ForEach(Array(feedingItems.enumerated()), id: \.element.id) { index, r in
                                    if index > 0 { Divider().padding(.leading, 16) }
                                    feedingRow(r)
                                        .contentShape(Rectangle())
                                        .onTapGesture { feedingToEdit = r }
                                        .contextMenu {
                                            Button {
                                                feedingToEdit = r
                                            } label: {
                                                Label(String(localized: "track.edit"), systemImage: "pencil")
                                            }
                                            Button {
                                                Haptic.success()
                                                vm.repeatFeeding(r)
                                            } label: {
                                                Label(String(localized: "track.repeat"), systemImage: "arrow.2.squarepath")
                                            }
                                            Button(role: .destructive) {
                                                recordToDelete = r
                                            } label: {
                                                Label(String(localized: "track.delete"), systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }

                        // Recent sleeps
                        if !recentSleeps.isEmpty {
                            let sleepItems = Array(recentSleeps.prefix(5))
                            recentSection(title: String(localized: "track.sleepSection"), color: .blSleep, totalCount: totalSleepCount, destination: AllSleepsView()) {
                                ForEach(Array(sleepItems.enumerated()), id: \.element.id) { index, r in
                                    if index > 0 { Divider().padding(.leading, 16) }
                                    sleepRow(r)
                                        .contentShape(Rectangle())
                                        .onTapGesture { sleepToEdit = r }
                                        .contextMenu {
                                            Button {
                                                sleepToEdit = r
                                            } label: {
                                                Label(String(localized: "track.edit"), systemImage: "pencil")
                                            }
                                            Button {
                                                Haptic.success()
                                                vm.repeatSleep(r)
                                            } label: {
                                                Label(String(localized: "track.repeat"), systemImage: "arrow.2.squarepath")
                                            }
                                            Button(role: .destructive) {
                                                recordToDelete = r
                                            } label: {
                                                Label(String(localized: "track.delete"), systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }

                        // Recent diapers
                        if !recentDiapers.isEmpty {
                            let diaperItems = Array(recentDiapers.prefix(5))
                            recentSection(title: String(localized: "track.diapers"), color: .blDiaper, totalCount: totalDiaperCount, destination: AllDiapersView()) {
                                ForEach(Array(diaperItems.enumerated()), id: \.element.id) { index, r in
                                    if index > 0 { Divider().padding(.leading, 16) }
                                    diaperRow(r)
                                        .contentShape(Rectangle())
                                        .onTapGesture { diaperToEdit = r }
                                        .contextMenu {
                                            Button {
                                                diaperToEdit = r
                                            } label: {
                                                Label(String(localized: "track.edit"), systemImage: "pencil")
                                            }
                                            Button {
                                                Haptic.success()
                                                vm.repeatDiaper(r)
                                            } label: {
                                                Label(String(localized: "track.repeat"), systemImage: "arrow.2.squarepath")
                                            }
                                            Button(role: .destructive) {
                                                recordToDelete = r
                                            } label: {
                                                Label(String(localized: "track.delete"), systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }

                        // Recent growth
                        if !recentGrowth.isEmpty {
                            let growthItems = Array(recentGrowth.prefix(5))
                            recentSection(title: String(localized: "track.growthSection"), color: .blGrowth, totalCount: totalGrowthCount, destination: AllGrowthView()) {
                                ForEach(Array(growthItems.enumerated()), id: \.element.id) { index, r in
                                    if index > 0 { Divider().padding(.leading, 16) }
                                    growthRow(r)
                                        .contentShape(Rectangle())
                                        .onTapGesture { growthToEdit = r }
                                        .contextMenu {
                                            Button {
                                                growthToEdit = r
                                            } label: {
                                                Label(String(localized: "track.edit"), systemImage: "pencil")
                                            }
                                            Button {
                                                Haptic.success()
                                                vm.repeatGrowth(r)
                                            } label: {
                                                Label(String(localized: "track.repeat"), systemImage: "arrow.2.squarepath")
                                            }
                                            Button(role: .destructive) {
                                                recordToDelete = r
                                            } label: {
                                                Label(String(localized: "track.delete"), systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }

                        Spacer(minLength: 100)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle(String(localized: "track.title"))
            .navigationBarTitleDisplayMode(.large)
            .onAppear { refreshPredicatesIfNeeded(); refreshTotalCounts(); startMinuteTimer() }
            .onDisappear { stopMinuteTimer() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshPredicatesIfNeeded(); refreshTotalCounts(); minuteTick = Date() }
            }
            .onChange(of: recentFeedings.count) { _, _ in refreshTotalCounts() }
            .onChange(of: recentSleeps.count) { _, _ in refreshTotalCounts() }
            .onChange(of: recentDiapers.count) { _, _ in refreshTotalCounts() }
            .onChange(of: recentGrowth.count) { _, _ in refreshTotalCounts() }
        }
        .sheet(isPresented: $showFeedingLog) { FeedingLogView(vm: vm) }
        .sheet(isPresented: $showSleepLog)   { SleepLogView(vm: vm) }
        .sheet(isPresented: $showDiaperLog)  { DiaperLogView(vm: vm) }
        .sheet(isPresented: $showGrowthLog)  { GrowthLogView(vm: vm) }
        // Edit sheets
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
        .alert(String(localized: "track.deleteRecord"), isPresented: Binding(
            get: { recordToDelete != nil },
            set: { if !$0 { recordToDelete = nil } }
        )) {
            Button(String(localized: "common.cancel"), role: .cancel) { recordToDelete = nil }
            Button(String(localized: "track.delete"), role: .destructive) {
                Haptic.warning()
                if let obj = recordToDelete {
                    // Determine record type for a contextual toast message
                    let (msg, icon, color): (String, String, Color) = {
                        if obj is CDFeedingRecord {
                            return (String(localized: "track.feedingDeleted"), "trash.fill", Color.blFeeding)
                        } else if obj is CDSleepRecord {
                            return (String(localized: "track.sleepDeleted"), "trash.fill", Color.blSleep)
                        } else if obj is CDDiaperRecord {
                            return (String(localized: "track.diaperDeleted"), "trash.fill", Color.blDiaper)
                        } else if obj is CDGrowthRecord {
                            return (String(localized: "track.growthDeleted"), "trash.fill", Color.blGrowth)
                        }
                        return (String(localized: "track.recordDeleted"), "trash.fill", Color.blPrimary)
                    }()
                    let success = vm.deleteObject(obj, in: ctx)
                    if success {
                        withAnimation { /* row removed */ }
                        appState.showToast(msg, icon: icon, color: color)
                    } else {
                        Haptic.error()
                        appState.showToast(String(localized: "common.deleteFailed"), icon: "exclamationmark.triangle.fill", color: .red)
                    }
                }
                recordToDelete = nil
            }
        } message: {
            Text(String(localized: "track.deleteConfirmMsg"))
        }
    }

    // MARK: - Predicate Refresh

    /// Re-compute the 14-day fetch window when the calendar day has changed
    /// since the last refresh (e.g. app survived past midnight in memory).
    private func refreshPredicatesIfNeeded() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard today != lastRefreshedDay else { return }
        lastRefreshedDay = today

        let windowStart = (cal.date(byAdding: .day, value: -14, to: today) ?? today) as NSDate
        recentFeedings.nsPredicate = NSPredicate(format: "timestamp >= %@", windowStart)
        recentSleeps.nsPredicate   = NSPredicate(format: "startTime >= %@", windowStart)
        recentDiapers.nsPredicate  = NSPredicate(format: "timestamp >= %@", windowStart)
    }

    // MARK: - Total Count Refresh

    /// Fetch total record counts for each entity to show in "See All (N)" badges.
    /// Uses lightweight `count(for:)` calls instead of loading full objects.
    private func refreshTotalCounts() {
        let context = PersistenceController.shared.container.viewContext

        let feedReq: NSFetchRequest<CDFeedingRecord> = CDFeedingRecord.fetchRequest()
        totalFeedingCount = (try? context.count(for: feedReq)) ?? 0

        let sleepReq: NSFetchRequest<CDSleepRecord> = CDSleepRecord.fetchRequest()
        totalSleepCount = (try? context.count(for: sleepReq)) ?? 0

        let diaperReq: NSFetchRequest<CDDiaperRecord> = CDDiaperRecord.fetchRequest()
        totalDiaperCount = (try? context.count(for: diaperReq)) ?? 0

        let growthReq: NSFetchRequest<CDGrowthRecord> = CDGrowthRecord.fetchRequest()
        totalGrowthCount = (try? context.count(for: growthReq)) ?? 0
    }

    // MARK: - Minute Timer (keeps "time since" hints fresh)

    private func startMinuteTimer() {
        stopMinuteTimer()
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            minuteTick = Date()
        }
    }

    private func stopMinuteTimer() {
        minuteTimer?.invalidate()
        minuteTimer = nil
    }

    // MARK: - Recent Section
    @ViewBuilder
    private func recentSection<Content: View, Dest: View>(title: String, color: Color, totalCount: Int, destination: Dest, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.blTextPrimary)
                Spacer()
                NavigationLink(destination: destination) {
                    HStack(spacing: 4) {
                        Text(String(localized: "track.seeAll"))
                            .font(.system(size: 14, weight: .medium))
                        if totalCount > 0 {
                            Text("(\(totalCount))")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .foregroundColor(.blPrimary)
                }
            }
            .padding(.horizontal, 20)
            VStack(spacing: 0) { content() }
                .blCard()
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Date Formatting Helpers

    /// Returns a short relative date prefix for non-today dates (e.g. "Yesterday", "Apr 3")
    private static func relativeDatePrefix(_ date: Date?) -> String? {
        guard let date else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return nil }
        if cal.isDateInYesterday(date) {
            return BLDateFormatters.relativeShort.string(from: date)
        }
        return BLDateFormatters.monthDay.string(from: date)
    }

    /// Formats time with optional relative date: "Yesterday · 8:00 PM" or just "8:00 PM"
    private static func timestampText(_ date: Date?) -> String {
        guard let date else { return "" }
        let time = date.formatted(date: .omitted, time: .shortened)
        if let prefix = relativeDatePrefix(date) {
            return "\(prefix) · \(time)"
        }
        return time
    }

    /// Whether a feeding record represents an ongoing timer (breast/pump with durationMinutes == 0).
    private static func isFeedingOngoing(_ r: CDFeedingRecord) -> Bool {
        let ft = FeedType(rawValue: r.feedType ?? "")
        let isTimerType = ft == .breast || ft == .pump
        return isTimerType && r.durationMinutes == 0
    }

    /// Whether there's an ongoing feeding timer (for QuickLogCard pulse animation)
    private var isFeedingActive: Bool {
        guard let first = recentFeedings.first else { return false }
        return Self.isFeedingOngoing(first)
    }

    /// Whether there's an ongoing sleep session (for QuickLogCard pulse animation)
    private var isSleepActive: Bool {
        guard let first = recentSleeps.first else { return false }
        return first.endTime == nil
    }

    private func feedingRow(_ r: CDFeedingRecord) -> some View {
        let unit = appState.measurementUnit
        let isOngoing = Self.isFeedingOngoing(r)
        let feedType = FeedType(rawValue: r.feedType ?? "")
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(feedType?.displayName ?? String(localized: "track.feeding"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.blTextPrimary)
                    if isOngoing {
                        Text(String(localized: "track.inProgress"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.blFeeding)
                            .clipShape(Capsule())
                    }
                }
                // Detail line: duration, amount, side
                HStack(spacing: 8) {
                    if !isOngoing && r.durationMinutes > 0 {
                        Text(DurationFormat.standard(r.durationMinutes))
                            .font(.system(size: 13))
                            .foregroundColor(.blTextSecondary)
                    }
                    if r.amountML > 0 {
                        let displayAmount = unit.volumeFromML(r.amountML)
                        Text(unit == .metric
                             ? "\(Int(displayAmount)) \(unit.volumeLabel)"
                             : String(format: "%.1f %@", displayAmount, unit.volumeLabel))
                            .font(.system(size: 13))
                            .foregroundColor(.blTextSecondary)
                    }
                    if let side = r.breastSide, !side.isEmpty {
                        Text(BreastSide(rawValue: side)?.displayName ?? side)
                            .font(.system(size: 13))
                            .foregroundColor(.blTextSecondary)
                    }
                }
                // Notes preview
                if let notes = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundColor(.blTextTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(Self.timestampText(r.timestamp))
                .font(.system(size: 13))
                .foregroundColor(.blTextTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(feedingRowAccessibilityLabel(r))
        .accessibilityHint(NSLocalizedString("a11y.longPressEditDelete", comment: ""))
    }

    private func feedingRowAccessibilityLabel(_ r: CDFeedingRecord) -> String {
        let unit = appState.measurementUnit
        let isOngoing = Self.isFeedingOngoing(r)
        let feedType = FeedType(rawValue: r.feedType ?? "")
        var parts: [String] = []
        parts.append(feedType?.displayName ?? String(localized: "track.feeding"))
        if isOngoing {
            parts.append(String(localized: "track.inProgress"))
        } else if r.durationMinutes > 0 {
            parts.append(DurationFormat.standard(r.durationMinutes))
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
        if let ts = r.timestamp {
            parts.append(String(format: NSLocalizedString("a11y.at %@", comment: ""), Self.timestampText(ts)))
        }
        if let notes = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            parts.append(String(format: NSLocalizedString("a11y.note %@", comment: ""), notes))
        }
        return parts.joined(separator: ", ")
    }

    private func sleepRow(_ r: CDSleepRecord) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let loc = r.location, let sl = SleepLocation(rawValue: loc) {
                        Text(sl.displayName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.blTextPrimary)
                    } else {
                        Text(String(localized: "track.sleep"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.blTextPrimary)
                    }
                    // Night / Nap category badge
                    let cat = SleepCategory.from(startTime: r.startTime)
                    Text("\(cat.icon) \(cat.label)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(cat == .night ? .blSleep : .orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((cat == .night ? Color.blSleep : Color.orange).opacity(0.12))
                        .clipShape(Capsule())
                    if r.endTime == nil {
                        Text(String(localized: "track.inProgress"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.blSleep)
                            .clipShape(Capsule())
                    }
                }
                // Time range: "8:00 PM – 6:00 AM" or "8:00 PM – …"
                HStack(spacing: 4) {
                    Text(r.startTime?.formatted(date: .omitted, time: .shortened) ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(.blTextTertiary)
                    if r.endTime != nil || r.startTime != nil {
                        Text("–")
                            .font(.system(size: 12))
                            .foregroundColor(.blTextTertiary)
                        Text(r.endTime?.formatted(date: .omitted, time: .shortened) ?? "…")
                            .font(.system(size: 12))
                            .foregroundColor(.blTextTertiary)
                    }
                }
                // Notes preview
                if let notes = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundColor(.blTextTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let s = r.startTime, let e = r.endTime {
                let mins = Int(e.timeIntervalSince(s) / 60)
                Text(DurationFormat.fromMinutes(mins))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blSleep)
            } else {
                Text(String(localized: "track.ongoing"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blSleep)
            }
            Text(Self.relativeDatePrefix(r.startTime) ?? "")
                .font(.system(size: 12))
                .foregroundColor(.blTextTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sleepRowAccessibilityLabel(r))
        .accessibilityHint(NSLocalizedString("a11y.longPressEditDelete", comment: ""))
    }

    private func sleepRowAccessibilityLabel(_ r: CDSleepRecord) -> String {
        var parts: [String] = []
        if let loc = r.location, let sl = SleepLocation(rawValue: loc) {
            parts.append(sl.displayName)
        } else {
            parts.append(String(localized: "track.sleep"))
        }
        if r.endTime == nil {
            parts.append(String(localized: "track.inProgress"))
        }
        if let s = r.startTime {
            let startStr = s.formatted(date: .omitted, time: .shortened)
            if let e = r.endTime {
                let endStr = e.formatted(date: .omitted, time: .shortened)
                parts.append("\(startStr) – \(endStr)")
                let mins = Int(e.timeIntervalSince(s) / 60)
                parts.append(DurationFormat.fromMinutes(mins))
            } else {
                parts.append(startStr)
            }
        }
        if let datePrefix = Self.relativeDatePrefix(r.startTime) {
            parts.append(datePrefix)
        }
        if let notes = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            parts.append(String(format: NSLocalizedString("a11y.note %@", comment: ""), notes))
        }
        return parts.joined(separator: ", ")
    }

    private func diaperRow(_ r: CDDiaperRecord) -> some View {
        let dtype = DiaperType(rawValue: r.diaperType ?? "")
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let dtype {
                        Text(dtype.icon)
                            .font(.system(size: 14))
                    }
                    Text(dtype?.displayName ?? String(localized: "track.diaper"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.blTextPrimary)
                }
                if let notes = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundColor(.blTextTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(Self.timestampText(r.timestamp))
                .font(.system(size: 13))
                .foregroundColor(.blTextTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(diaperRowAccessibilityLabel(r))
        .accessibilityHint(NSLocalizedString("a11y.longPressEditDelete", comment: ""))
    }

    private func diaperRowAccessibilityLabel(_ r: CDDiaperRecord) -> String {
        var parts: [String] = []
        if let dtype = DiaperType(rawValue: r.diaperType ?? "") {
            parts.append(dtype.displayName)
        } else {
            parts.append(String(localized: "track.diaper"))
        }
        if let ts = r.timestamp {
            parts.append(String(format: NSLocalizedString("a11y.at %@", comment: ""), Self.timestampText(ts)))
        }
        if let notes = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            parts.append(String(format: NSLocalizedString("a11y.note %@", comment: ""), notes))
        }
        return parts.joined(separator: ", ")
    }

    private func growthRow(_ r: CDGrowthRecord) -> some View {
        let unit = appState.measurementUnit
        let baby = appState.currentBaby
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(String(localized: "track.growth"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.blTextPrimary)
                    // Baby's age at this measurement
                    if let baby, let date = r.date {
                        Text(baby.ageText(at: date))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.blGrowth)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blGrowth.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                // Measurement pills
                HStack(spacing: 6) {
                    if r.weightKG > 0 {
                        let w = unit.weightFromKG(r.weightKG)
                        growthMetricPill(
                            icon: "scalemass.fill",
                            text: String(format: "%.2f %@", w, unit.weightLabel)
                        )
                    }
                    if r.heightCM > 0 {
                        let h = unit.lengthFromCM(r.heightCM)
                        growthMetricPill(
                            icon: "ruler.fill",
                            text: String(format: "%.1f %@", h, unit.heightLabel)
                        )
                    }
                    if r.headCircumferenceCM > 0 {
                        let hc = unit.lengthFromCM(r.headCircumferenceCM)
                        growthMetricPill(
                            icon: "circle.dashed",
                            text: String(format: "%.1f %@", hc, unit.heightLabel)
                        )
                    }
                }
                // Notes preview
                if let notes = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundColor(.blTextTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(r.date.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "—")
                .font(.system(size: 13))
                .foregroundColor(.blTextTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(growthRowAccessibilityLabel(r))
        .accessibilityHint(NSLocalizedString("a11y.longPressEditDelete", comment: ""))
    }

    private func growthRowAccessibilityLabel(_ r: CDGrowthRecord) -> String {
        let unit = appState.measurementUnit
        let baby = appState.currentBaby
        var parts: [String] = []
        parts.append(String(localized: "track.growth"))
        if let baby, let date = r.date {
            parts.append(String(format: NSLocalizedString("a11y.atAge %@", comment: ""), baby.ageText(at: date)))
        }
        if r.weightKG > 0 {
            let w = unit.weightFromKG(r.weightKG)
            parts.append("\(String(format: "%.2f", w)) \(unit.weightLabel)")
        }
        if r.heightCM > 0 {
            let h = unit.lengthFromCM(r.heightCM)
            parts.append("\(String(format: "%.1f", h)) \(unit.heightLabel)")
        }
        if r.headCircumferenceCM > 0 {
            let hc = unit.lengthFromCM(r.headCircumferenceCM)
            parts.append(String(format: NSLocalizedString("a11y.trackView.headCirc %@", comment: ""), "\(String(format: "%.1f", hc)) \(unit.heightLabel)"))
        }
        if let date = r.date {
            parts.append(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))
        }
        if let notes = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            parts.append(String(format: NSLocalizedString("a11y.note %@", comment: ""), notes))
        }
        return parts.joined(separator: ", ")
    }

    /// Compact pill showing a growth metric with its icon for visual disambiguation.
    private func growthMetricPill(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.blGrowth.opacity(0.7))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.blGrowth)
        }
        .lineLimit(1)
    }
}
