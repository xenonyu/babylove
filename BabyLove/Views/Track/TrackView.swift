import SwiftUI
import CoreData

struct TrackView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) var ctx
    @StateObject private var vm: TrackViewModel = TrackViewModel(context: PersistenceController.shared.container.viewContext)

    @State private var showFeedingLog  = false
    @State private var showSleepLog    = false
    @State private var showDiaperLog   = false
    @State private var showGrowthLog   = false
    @State private var recordToDelete: NSManagedObject?

    // Edit states
    @State private var feedingToEdit: CDFeedingRecord?
    @State private var sleepToEdit: CDSleepRecord?
    @State private var diaperToEdit: CDDiaperRecord?
    @State private var growthToEdit: CDGrowthRecord?

    @FetchRequest(
        entity: CDFeedingRecord.entity(),
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)]
    ) private var recentFeedings: FetchedResults<CDFeedingRecord>

    @FetchRequest(
        entity: CDSleepRecord.entity(),
        sortDescriptors: [NSSortDescriptor(key: "startTime", ascending: false)]
    ) private var recentSleeps: FetchedResults<CDSleepRecord>

    @FetchRequest(
        entity: CDDiaperRecord.entity(),
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)]
    ) private var recentDiapers: FetchedResults<CDDiaperRecord>

    @FetchRequest(
        entity: CDGrowthRecord.entity(),
        sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
    ) private var recentGrowth: FetchedResults<CDGrowthRecord>

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Quick log grid
                        VStack(spacing: 12) {
                            BLSectionHeader(title: "Log Activity")
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
                                Text("No records yet")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.blTextPrimary)
                                Text("Tap one of the buttons above to start\ntracking your baby's day")
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
                            recentSection(title: "Feedings", color: .blFeeding, destination: AllFeedingsView()) {
                                ForEach(recentFeedings.prefix(5)) { r in
                                    feedingRow(r)
                                        .contentShape(Rectangle())
                                        .onTapGesture { feedingToEdit = r }
                                        .contextMenu {
                                            Button {
                                                feedingToEdit = r
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            Button(role: .destructive) {
                                                recordToDelete = r
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }

                        // Recent sleeps
                        if !recentSleeps.isEmpty {
                            recentSection(title: "Sleep", color: .blSleep, destination: AllSleepsView()) {
                                ForEach(recentSleeps.prefix(5)) { r in
                                    sleepRow(r)
                                        .contentShape(Rectangle())
                                        .onTapGesture { sleepToEdit = r }
                                        .contextMenu {
                                            Button {
                                                sleepToEdit = r
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            Button(role: .destructive) {
                                                recordToDelete = r
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }

                        // Recent diapers
                        if !recentDiapers.isEmpty {
                            recentSection(title: "Diapers", color: .blDiaper, destination: AllDiapersView()) {
                                ForEach(recentDiapers.prefix(5)) { r in
                                    diaperRow(r)
                                        .contentShape(Rectangle())
                                        .onTapGesture { diaperToEdit = r }
                                        .contextMenu {
                                            Button {
                                                diaperToEdit = r
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            Button(role: .destructive) {
                                                recordToDelete = r
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }

                        // Recent growth
                        if !recentGrowth.isEmpty {
                            recentSection(title: "Growth", color: .blGrowth, destination: AllGrowthView()) {
                                ForEach(recentGrowth.prefix(5)) { r in
                                    growthRow(r)
                                        .contentShape(Rectangle())
                                        .onTapGesture { growthToEdit = r }
                                        .contextMenu {
                                            Button {
                                                growthToEdit = r
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            Button(role: .destructive) {
                                                recordToDelete = r
                                            } label: {
                                                Label("Delete", systemImage: "trash")
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
            .navigationTitle("Track")
            .navigationBarTitleDisplayMode(.large)
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
        .alert("Delete Record?", isPresented: Binding(
            get: { recordToDelete != nil },
            set: { if !$0 { recordToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { recordToDelete = nil }
            Button("Delete", role: .destructive) {
                Haptic.warning()
                if let obj = recordToDelete {
                    // Determine record type for a contextual toast message
                    let (msg, icon, color): (String, String, Color) = {
                        if obj is CDFeedingRecord {
                            return ("Feeding deleted", "trash.fill", Color.blFeeding)
                        } else if obj is CDSleepRecord {
                            return ("Sleep deleted", "trash.fill", Color.blSleep)
                        } else if obj is CDDiaperRecord {
                            return ("Diaper deleted", "trash.fill", Color.blDiaper)
                        } else if obj is CDGrowthRecord {
                            return ("Growth record deleted", "trash.fill", Color.blGrowth)
                        }
                        return ("Record deleted", "trash.fill", Color.blPrimary)
                    }()
                    withAnimation { vm.deleteObject(obj, in: ctx) }
                    appState.showToast(msg, icon: icon, color: color)
                }
                recordToDelete = nil
            }
        } message: {
            Text("This record will be permanently removed.")
        }
    }

    // MARK: - Recent Section
    @ViewBuilder
    private func recentSection<Content: View, Dest: View>(title: String, color: Color, destination: Dest, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.blTextPrimary)
                Spacer()
                NavigationLink(destination: destination) {
                    Text("See All")
                        .font(.system(size: 14, weight: .medium))
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

    private func feedingRow(_ r: CDFeedingRecord) -> some View {
        let unit = appState.measurementUnit
        let isOngoing = Self.isFeedingOngoing(r)
        let feedType = FeedType(rawValue: r.feedType ?? "")
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(feedType?.displayName ?? "Feeding")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.blTextPrimary)
                    if isOngoing {
                        Text("In Progress")
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
                        Text("\(r.durationMinutes) min")
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
                if let notes = r.notes, !notes.isEmpty {
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
                        Text("Sleep")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.blTextPrimary)
                    }
                    if r.endTime == nil {
                        Text("In Progress")
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
                if let notes = r.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundColor(.blTextTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let s = r.startTime, let e = r.endTime {
                let mins = Int(e.timeIntervalSince(s) / 60)
                let h = mins / 60, m = mins % 60
                Text(h > 0 ? "\(h)h \(m)m" : "\(m)m")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blSleep)
            } else {
                Text("Ongoing")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blSleep)
            }
            Text(Self.relativeDatePrefix(r.startTime) ?? "")
                .font(.system(size: 12))
                .foregroundColor(.blTextTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                    Text(dtype?.displayName ?? "Diaper")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.blTextPrimary)
                }
                if let notes = r.notes, !notes.isEmpty {
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
    }

    private func growthRow(_ r: CDGrowthRecord) -> some View {
        let unit = appState.measurementUnit
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Growth")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.blTextPrimary)
                // Measurement pills
                HStack(spacing: 6) {
                    if r.weightKG > 0 {
                        let w = unit.weightFromKG(r.weightKG)
                        growthMetricPill(
                            icon: "scalemass.fill",
                            text: String(format: "%.1f %@", w, unit.weightLabel)
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
                if let notes = r.notes, !notes.isEmpty {
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
