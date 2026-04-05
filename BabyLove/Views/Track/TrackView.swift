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

                        // Recent feedings
                        if !recentFeedings.isEmpty {
                            recentSection(title: "Feedings", color: .blFeeding) {
                                ForEach(recentFeedings.prefix(5)) { r in
                                    feedingRow(r)
                                        .contextMenu {
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
                            recentSection(title: "Sleep", color: .blSleep) {
                                ForEach(recentSleeps.prefix(5)) { r in
                                    sleepRow(r)
                                        .contextMenu {
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
                            recentSection(title: "Diapers", color: .blDiaper) {
                                ForEach(recentDiapers.prefix(5)) { r in
                                    diaperRow(r)
                                        .contextMenu {
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
        .alert("Delete Record?", isPresented: Binding(
            get: { recordToDelete != nil },
            set: { if !$0 { recordToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { recordToDelete = nil }
            Button("Delete", role: .destructive) {
                if let obj = recordToDelete {
                    withAnimation { vm.deleteObject(obj, in: ctx) }
                }
                recordToDelete = nil
            }
        } message: {
            Text("This record will be permanently removed.")
        }
    }

    // MARK: - Recent Section
    @ViewBuilder
    private func recentSection<Content: View>(title: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12) {
            BLSectionHeader(title: title)
                .padding(.horizontal, 20)
            VStack(spacing: 0) { content() }
                .blCard()
                .padding(.horizontal, 20)
        }
    }

    private func feedingRow(_ r: CDFeedingRecord) -> some View {
        let unit = appState.measurementUnit
        return HStack {
            Text(FeedType(rawValue: r.feedType ?? "")?.displayName ?? "Feeding")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.blTextPrimary)
            Spacer()
            if r.durationMinutes > 0 {
                Text("\(r.durationMinutes)m")
                    .font(.system(size: 14))
                    .foregroundColor(.blFeeding)
            }
            if r.amountML > 0 {
                let displayAmount = unit.volumeFromML(r.amountML)
                Text(unit == .metric
                     ? "\(Int(displayAmount))\(unit.volumeLabel)"
                     : String(format: "%.1f\(unit.volumeLabel)", displayAmount))
                    .font(.system(size: 14))
                    .foregroundColor(.blFeeding)
            }
            Text(r.timestamp?.formatted(date: .omitted, time: .shortened) ?? "")
                .font(.system(size: 13))
                .foregroundColor(.blTextTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func sleepRow(_ r: CDSleepRecord) -> some View {
        HStack {
            Text("Sleep")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.blTextPrimary)
            Spacer()
            if let s = r.startTime, let e = r.endTime {
                let mins = Int(e.timeIntervalSince(s) / 60)
                let h = mins / 60, m = mins % 60
                Text(h > 0 ? "\(h)h \(m)m" : "\(m)m")
                    .font(.system(size: 14))
                    .foregroundColor(.blSleep)
            } else {
                Text("Ongoing")
                    .font(.system(size: 14))
                    .foregroundColor(.blSleep)
            }
            Text(r.startTime?.formatted(date: .omitted, time: .shortened) ?? "")
                .font(.system(size: 13))
                .foregroundColor(.blTextTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func diaperRow(_ r: CDDiaperRecord) -> some View {
        HStack {
            Text(DiaperType(rawValue: r.diaperType ?? "")?.displayName ?? "Diaper")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.blTextPrimary)
            Spacer()
            Text(r.timestamp?.formatted(date: .omitted, time: .shortened) ?? "")
                .font(.system(size: 13))
                .foregroundColor(.blTextTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
