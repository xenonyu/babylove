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

    // Initialize with today's predicate to avoid flashing all-time data
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.timestamp, order: .reverse)],
        predicate: NSPredicate(format: "timestamp >= %@", Calendar.current.startOfDay(for: Date()) as NSDate)
    )
    private var todayFeedings: FetchedResults<CDFeedingRecord>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.startTime, order: .reverse)],
        predicate: NSPredicate(format: "startTime >= %@", Calendar.current.startOfDay(for: Date()) as NSDate)
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

    private var baby: Baby? { appState.currentBaby }

    /// Refresh predicates to reflect current calendar day.
    /// Called on appear AND when returning from background to handle midnight crossover.
    private func updatePredicates() {
        let startOfDay = Calendar.current.startOfDay(for: Date()) as NSDate
        todayFeedings.nsPredicate = NSPredicate(format: "timestamp >= %@", startOfDay)
        todaySleeps.nsPredicate   = NSPredicate(format: "startTime >= %@", startOfDay)
        todayDiapers.nsPredicate  = NSPredicate(format: "timestamp >= %@", startOfDay)
    }

    /// Total feeding volume in ml for today (sum of all amountML values)
    private var totalFeedingVolumeML: Double {
        todayFeedings.reduce(0.0) { sum, r in sum + r.amountML }
    }

    /// Formatted feeding volume subtitle (e.g. "480 ml" or "16.0 oz"), empty if no volume recorded
    private var feedingVolumeSubtitle: String {
        guard totalFeedingVolumeML > 0 else { return "" }
        let unit = appState.measurementUnit
        let display = unit.volumeFromML(totalFeedingVolumeML)
        if unit == .metric {
            return "\(Int(display)) \(unit.volumeLabel)"
        } else {
            return String(format: "%.1f \(unit.volumeLabel)", display)
        }
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

    private var totalSleepMinutes: Int {
        todaySleeps.reduce(0) { sum, r in
            guard let s = r.startTime else { return sum }
            // Use current time for ongoing sleep (endTime == nil)
            let e = r.endTime ?? Date()
            return sum + Int(e.timeIntervalSince(s) / 60)
        }
    }

    private var sleepText: String {
        let h = totalSleepMinutes / 60
        let m = totalSleepMinutes % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.blBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Baby hero card
                        babyHeroCard

                        // Ongoing sleep banner
                        if let ongoing = ongoingSleep {
                            ongoingSleepBanner(ongoing)
                                .padding(.horizontal, 20)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Today stats
                        VStack(spacing: 12) {
                            BLSectionHeader(title: "Today's Summary")
                                .padding(.horizontal, 20)

                            HStack(spacing: 12) {
                                StatBadge(value: "\(todayFeedings.count)",
                                          label: "Feedings",
                                          color: .blFeeding,
                                          subtitle: feedingVolumeSubtitle)
                                StatBadge(value: sleepText.isEmpty ? "0m" : sleepText,
                                          label: "Sleep",
                                          color: .blSleep)
                                StatBadge(value: "\(todayDiapers.count)",
                                          label: "Diapers",
                                          color: .blDiaper,
                                          subtitle: diaperBreakdownSubtitle)
                            }
                            .padding(.horizontal, 20)
                        }

                        // Quick log
                        VStack(spacing: 12) {
                            BLSectionHeader(title: "Quick Log")
                                .padding(.horizontal, 20)

                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 12) {
                                QuickLogCard(icon: "drop.fill",
                                             label: "Feeding",
                                             color: .blFeeding) { showFeedingLog = true }
                                QuickLogCard(icon: "moon.zzz.fill",
                                             label: "Sleep",
                                             color: .blSleep) { showSleepLog = true }
                                QuickLogCard(icon: "oval.fill",
                                             label: "Diaper",
                                             color: .blDiaper) { showDiaperLog = true }
                                QuickLogCard(icon: "chart.bar.fill",
                                             label: "Growth",
                                             color: .blGrowth) { showGrowthLog = true }
                            }
                            .padding(.horizontal, 20)
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
                startSleepTimerIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    updatePredicates()
                    startSleepTimerIfNeeded()
                } else if phase == .background {
                    stopSleepTimer()
                }
            }
            .onChange(of: ongoingSleeps.count) { _, count in
                if count > 0 {
                    startSleepTimerIfNeeded()
                } else {
                    stopSleepTimer()
                }
            }
        }
        .sheet(isPresented: $showFeedingLog) {
            FeedingLogView(vm: vm)
        }
        .sheet(isPresented: $showSleepLog) {
            SleepLogView(vm: vm)
        }
        .sheet(isPresented: $showDiaperLog) {
            DiaperLogView(vm: vm)
        }
        .sheet(isPresented: $showGrowthLog) {
            GrowthLogView(vm: vm)
        }
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
        withAnimation(.spring(response: 0.4)) {
            vm.endSleepByID(id, context: ctx)
        }
        stopSleepTimer()
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
                endOngoingSleep()
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
    }

    // MARK: - Baby Hero Card

    private var babyHeroCard: some View {
        HStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color(hex: baby?.gender.color ?? "#FF7B6B").opacity(0.2))
                    .frame(width: 64, height: 64)
                Text(baby?.gender.icon ?? "🍼")
                    .font(.system(size: 32))
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

                Text("No activity yet today")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blTextSecondary)

                Text("Tap a Quick Log button above to start tracking \(baby?.name ?? "baby")'s day")
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
        return days == 1 ? "Yesterday" : "\(days)d ago"
    }

    /// Build a short detail string for the last feeding (e.g. "15m · Left" or "120 ml")
    private func feedingDetail(_ r: CDFeedingRecord) -> String {
        let unit = appState.measurementUnit
        var parts: [String] = []
        if r.durationMinutes > 0 {
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

    private var recentActivitySection: some View {
        VStack(spacing: 12) {
            BLSectionHeader(title: "Recent Activity")
                .padding(.horizontal, 20)

            VStack(spacing: 1) {
                if let last = todayFeedings.first {
                    let feedType = FeedType(rawValue: last.feedType ?? "")
                    TimeSinceRow(
                        icon: feedType?.icon ?? "drop.fill",
                        color: .blFeeding,
                        title: feedType?.displayName ?? "Feeding",
                        detail: feedingDetail(last),
                        timeAgo: last.timestamp.map { Self.timeAgoText(from: $0) } ?? "",
                        timeLabel: last.timestamp?.formatted(date: .omitted, time: .shortened) ?? ""
                    )
                    if !todaySleeps.isEmpty || !todayDiapers.isEmpty {
                        Divider().padding(.leading, 70)
                    }
                }
                if let last = todaySleeps.first {
                    let sleepDetail: String = {
                        if last.endTime == nil {
                            return "Ongoing"
                        } else if let s = last.startTime, let e = last.endTime {
                            let mins = Int(e.timeIntervalSince(s) / 60)
                            let h = mins / 60, m = mins % 60
                            return h > 0 ? "\(h)h \(m)m" : "\(m)m"
                        }
                        return ""
                    }()
                    let sleepAgo: String = {
                        if last.endTime == nil {
                            return "Now"
                        } else if let endTime = last.endTime {
                            return Self.timeAgoText(from: endTime)
                        }
                        return ""
                    }()
                    TimeSinceRow(
                        icon: "moon.zzz.fill",
                        color: .blSleep,
                        title: "Sleep",
                        detail: sleepDetail,
                        timeAgo: sleepAgo,
                        timeLabel: last.startTime?.formatted(date: .omitted, time: .shortened) ?? ""
                    )
                    if !todayDiapers.isEmpty {
                        Divider().padding(.leading, 70)
                    }
                }
                if let last = todayDiapers.first {
                    let dType = DiaperType(rawValue: last.diaperType ?? "")
                    TimeSinceRow(
                        icon: "oval.fill",
                        color: .blDiaper,
                        title: dType?.displayName ?? "Diaper",
                        detail: dType?.icon ?? "",
                        timeAgo: last.timestamp.map { Self.timeAgoText(from: $0) } ?? "",
                        timeLabel: last.timestamp?.formatted(date: .omitted, time: .shortened) ?? ""
                    )
                }
            }
            .blCard()
            .padding(.horizontal, 20)
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
            }
            Spacer()
            Text(timeAgo)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
