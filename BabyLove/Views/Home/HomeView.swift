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
                                          color: .blFeeding)
                                StatBadge(value: sleepText.isEmpty ? "0m" : sleepText,
                                          label: "Sleep",
                                          color: .blSleep)
                                StatBadge(value: "\(todayDiapers.count)",
                                          label: "Diapers",
                                          color: .blDiaper)
                            }
                            .padding(.horizontal, 20)
                        }

                        // Quick log
                        VStack(spacing: 12) {
                            BLSectionHeader(title: "Quick Log")
                                .padding(.horizontal, 20)

                            HStack(spacing: 12) {
                                QuickLogCard(icon: "drop.fill",
                                             label: "Feeding",
                                             color: .blFeeding) { showFeedingLog = true }
                                QuickLogCard(icon: "moon.fill",
                                             label: "Sleep",
                                             color: .blSleep) { showSleepLog = true }
                                QuickLogCard(icon: "oval.fill",
                                             label: "Diaper",
                                             color: .blDiaper) { showDiaperLog = true }
                            }
                            .padding(.horizontal, 20)
                        }

                        // Recent activity
                        if !todayFeedings.isEmpty || !todaySleeps.isEmpty || !todayDiapers.isEmpty {
                            recentActivitySection
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

    // MARK: - Recent Activity

    private var recentActivitySection: some View {
        VStack(spacing: 12) {
            BLSectionHeader(title: "Recent Activity")
                .padding(.horizontal, 20)

            VStack(spacing: 1) {
                if let last = todayFeedings.first {
                    ActivityRow(
                        icon: "drop.fill",
                        color: .blFeeding,
                        title: FeedType(rawValue: last.feedType ?? "")?.displayName ?? "Feeding",
                        subtitle: last.timestamp?.formatted(date: .omitted, time: .shortened) ?? ""
                    )
                }
                if let last = todaySleeps.first {
                    ActivityRow(
                        icon: "moon.fill",
                        color: .blSleep,
                        title: "Sleep",
                        subtitle: last.startTime?.formatted(date: .omitted, time: .shortened) ?? ""
                    )
                }
                if let last = todayDiapers.first {
                    ActivityRow(
                        icon: "oval.fill",
                        color: .blDiaper,
                        title: DiaperType(rawValue: last.diaperType ?? "")?.displayName ?? "Diaper",
                        subtitle: last.timestamp?.formatted(date: .omitted, time: .shortened) ?? ""
                    )
                }
            }
            .blCard()
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Activity Row
struct ActivityRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

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
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.blTextPrimary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.blTextSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.blTextTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
