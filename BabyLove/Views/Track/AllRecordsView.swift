import SwiftUI
import CoreData

// MARK: - All Feedings
struct AllFeedingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) var ctx
    @StateObject private var vm = TrackViewModel(context: PersistenceController.shared.container.viewContext)
    @State private var recordToDelete: CDFeedingRecord?
    @State private var recordToEdit: CDFeedingRecord?

    @FetchRequest(
        entity: CDFeedingRecord.entity(),
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)]
    ) private var records: FetchedResults<CDFeedingRecord>

    var body: some View {
        ZStack {
            Color.blBackground.ignoresSafeArea()

            if records.isEmpty {
                emptyState("No feeding records yet", icon: "drop.fill", color: .blFeeding)
            } else {
                List {
                    ForEach(groupedByDate(records, keyPath: \.timestamp), id: \.key) { section in
                        Section {
                            ForEach(section.records) { r in
                                feedingRow(r)
                                    .listRowBackground(Color.blCard)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .contentShape(Rectangle())
                                    .onTapGesture { recordToEdit = r }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) { recordToDelete = r } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button { recordToEdit = r } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.blFeeding)
                                    }
                            }
                        } header: {
                            Text(section.key)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("All Feedings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $recordToEdit) { record in
            FeedingLogView(vm: vm, editingRecord: record)
        }
        .alert("Delete Record?", isPresented: Binding(
            get: { recordToDelete != nil },
            set: { if !$0 { recordToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { recordToDelete = nil }
            Button("Delete", role: .destructive) {
                Haptic.warning()
                if let obj = recordToDelete {
                    withAnimation { vm.deleteObject(obj, in: ctx) }
                    appState.showToast("Feeding deleted", icon: "trash.fill", color: .blFeeding)
                }
                recordToDelete = nil
            }
        } message: {
            Text("This record will be permanently removed.")
        }
    }

    private func feedingRow(_ r: CDFeedingRecord) -> some View {
        let unit = appState.measurementUnit
        return HStack(spacing: 12) {
            let feedType = FeedType(rawValue: r.feedType ?? "")
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.blFeeding.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: feedType?.icon ?? "drop.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.blFeeding)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(feedType?.displayName ?? "Feeding")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.blTextPrimary)
                HStack(spacing: 8) {
                    if r.durationMinutes > 0 {
                        Text("\(r.durationMinutes) min")
                            .font(.system(size: 13))
                            .foregroundColor(.blTextSecondary)
                    }
                    if r.amountML > 0 {
                        let displayAmount = unit.volumeFromML(r.amountML)
                        Text(unit == .metric
                             ? "\(Int(displayAmount)) \(unit.volumeLabel)"
                             : String(format: "%.1f \(unit.volumeLabel)", displayAmount))
                            .font(.system(size: 13))
                            .foregroundColor(.blTextSecondary)
                    }
                    if let side = r.breastSide, !side.isEmpty {
                        Text(BreastSide(rawValue: side)?.displayName ?? side)
                            .font(.system(size: 13))
                            .foregroundColor(.blTextSecondary)
                    }
                }
                if let notes = r.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundColor(.blTextTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(r.timestamp?.formatted(date: .omitted, time: .shortened) ?? "")
                .font(.system(size: 13))
                .foregroundColor(.blTextTertiary)
        }
    }
}

// MARK: - All Sleeps
struct AllSleepsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) var ctx
    @StateObject private var vm = TrackViewModel(context: PersistenceController.shared.container.viewContext)
    @State private var recordToDelete: CDSleepRecord?
    @State private var recordToEdit: CDSleepRecord?

    @FetchRequest(
        entity: CDSleepRecord.entity(),
        sortDescriptors: [NSSortDescriptor(key: "startTime", ascending: false)]
    ) private var records: FetchedResults<CDSleepRecord>

    var body: some View {
        ZStack {
            Color.blBackground.ignoresSafeArea()

            if records.isEmpty {
                emptyState("No sleep records yet", icon: "moon.zzz.fill", color: .blSleep)
            } else {
                List {
                    ForEach(groupedByDate(records, keyPath: \.startTime), id: \.key) { section in
                        Section {
                            ForEach(section.records) { r in
                                sleepRow(r)
                                    .listRowBackground(Color.blCard)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .contentShape(Rectangle())
                                    .onTapGesture { recordToEdit = r }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) { recordToDelete = r } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button { recordToEdit = r } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.blSleep)
                                    }
                            }
                        } header: {
                            Text(section.key)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("All Sleep")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $recordToEdit) { record in
            SleepLogView(vm: vm, editingRecord: record)
        }
        .alert("Delete Record?", isPresented: Binding(
            get: { recordToDelete != nil },
            set: { if !$0 { recordToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { recordToDelete = nil }
            Button("Delete", role: .destructive) {
                Haptic.warning()
                if let obj = recordToDelete {
                    withAnimation { vm.deleteObject(obj, in: ctx) }
                    appState.showToast("Sleep record deleted", icon: "trash.fill", color: .blSleep)
                }
                recordToDelete = nil
            }
        } message: {
            Text("This record will be permanently removed.")
        }
    }

    private func sleepRow(_ r: CDSleepRecord) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.blSleep.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.blSleep)
            }

            VStack(alignment: .leading, spacing: 3) {
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

                    if let s = r.startTime, let e = r.endTime {
                        let mins = Int(e.timeIntervalSince(s) / 60)
                        let h = mins / 60, m = mins % 60
                        Text(h > 0 ? "\(h)h \(m)m" : "\(m)m")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.blSleep)
                    } else {
                        Text("Ongoing")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.blSleep)
                    }
                }

                HStack(spacing: 4) {
                    Text(r.startTime?.formatted(date: .omitted, time: .shortened) ?? "")
                    if r.endTime != nil {
                        Text("–")
                        Text(r.endTime?.formatted(date: .omitted, time: .shortened) ?? "")
                    }
                }
                .font(.system(size: 13))
                .foregroundColor(.blTextSecondary)

                if let notes = r.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundColor(.blTextTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
    }
}

// MARK: - All Diapers
struct AllDiapersView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) var ctx
    @StateObject private var vm = TrackViewModel(context: PersistenceController.shared.container.viewContext)
    @State private var recordToDelete: CDDiaperRecord?
    @State private var recordToEdit: CDDiaperRecord?

    @FetchRequest(
        entity: CDDiaperRecord.entity(),
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)]
    ) private var records: FetchedResults<CDDiaperRecord>

    var body: some View {
        ZStack {
            Color.blBackground.ignoresSafeArea()

            if records.isEmpty {
                emptyState("No diaper records yet", icon: "oval.fill", color: .blDiaper)
            } else {
                List {
                    ForEach(groupedByDate(records, keyPath: \.timestamp), id: \.key) { section in
                        Section {
                            ForEach(section.records) { r in
                                diaperRow(r)
                                    .listRowBackground(Color.blCard)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .contentShape(Rectangle())
                                    .onTapGesture { recordToEdit = r }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) { recordToDelete = r } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button { recordToEdit = r } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.blDiaper)
                                    }
                            }
                        } header: {
                            Text(section.key)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("All Diapers")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $recordToEdit) { record in
            DiaperLogView(vm: vm, editingRecord: record)
        }
        .alert("Delete Record?", isPresented: Binding(
            get: { recordToDelete != nil },
            set: { if !$0 { recordToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { recordToDelete = nil }
            Button("Delete", role: .destructive) {
                Haptic.warning()
                if let obj = recordToDelete {
                    withAnimation { vm.deleteObject(obj, in: ctx) }
                    appState.showToast("Diaper record deleted", icon: "trash.fill", color: .blDiaper)
                }
                recordToDelete = nil
            }
        } message: {
            Text("This record will be permanently removed.")
        }
    }

    private func diaperRow(_ r: CDDiaperRecord) -> some View {
        let diaperType = DiaperType(rawValue: r.diaperType ?? "")
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.blDiaper.opacity(0.15))
                    .frame(width: 40, height: 40)
                Text(diaperType?.icon ?? "💧")
                    .font(.system(size: 18))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(diaperType?.displayName ?? "Diaper")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.blTextPrimary)
                if let notes = r.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundColor(.blTextTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(r.timestamp?.formatted(date: .omitted, time: .shortened) ?? "")
                .font(.system(size: 13))
                .foregroundColor(.blTextTertiary)
        }
    }
}

// MARK: - Shared Helpers

private struct DateSection<T>: Identifiable {
    let key: String
    let records: [T]
    var id: String { key }
}

private func groupedByDate<T: NSManagedObject>(_ results: FetchedResults<T>, keyPath: KeyPath<T, Date?>) -> [DateSection<T>] {
    let cal = Calendar.current
    var dict: [String: [T]] = [:]
    var order: [String] = []

    for record in results {
        let date = record[keyPath: keyPath] ?? Date()
        let key: String
        if cal.isDateInToday(date) || cal.isDateInYesterday(date) {
            key = BLDateFormatters.relativeMedium.string(from: date)
        } else {
            key = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        }
        if dict[key] == nil { order.append(key) }
        dict[key, default: []].append(record)
    }

    return order.compactMap { key in
        guard let records = dict[key] else { return nil }
        return DateSection(key: key, records: records)
    }
}

@ViewBuilder
private func emptyState(_ message: String, icon: String, color: Color) -> some View {
    VStack(spacing: 16) {
        Image(systemName: icon)
            .font(.system(size: 48))
            .foregroundColor(color.opacity(0.4))
        Text(message)
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(.blTextSecondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
