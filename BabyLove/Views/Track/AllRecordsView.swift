import SwiftUI
import CoreData

// MARK: - All Feedings
struct AllFeedingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) var ctx
    @StateObject private var vm = TrackViewModel(context: PersistenceController.shared.container.viewContext)
    @State private var recordToDelete: CDFeedingRecord?
    @State private var recordToEdit: CDFeedingRecord?
    @State private var showAddSheet = false
    @State private var selectedFilter: FeedType? = nil

    @FetchRequest(
        entity: CDFeedingRecord.entity(),
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)]
    ) private var records: FetchedResults<CDFeedingRecord>

    private var filteredRecords: [CDFeedingRecord] {
        guard let filter = selectedFilter else { return Array(records) }
        return records.filter { FeedType(rawValue: $0.feedType ?? "") == filter }
    }

    /// Count of records for a given feed type (for chip badge)
    private func countFor(_ type: FeedType) -> Int {
        records.filter { FeedType(rawValue: $0.feedType ?? "") == type }.count
    }

    var body: some View {
        ZStack {
            Color.blBackground.ignoresSafeArea()

            if records.isEmpty {
                emptyState(String(localized: "allRecords.noFeedingsYet"), icon: "drop.fill", color: .blFeeding)
            } else {
                VStack(spacing: 0) {
                    // Filter chips
                    feedingFilterBar

                    if filteredRecords.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 36))
                                .foregroundColor(.blFeeding.opacity(0.4))
                            Text(String(localized: "allRecords.noFilteredFeedings \(selectedFilter?.displayName ?? "")"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.blTextSecondary)
                            Button {
                                withAnimation(.spring(response: 0.3)) { selectedFilter = nil }
                            } label: {
                                Text(String(localized: "allRecords.showAll"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.blFeeding)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        List {
                            ForEach(groupedByDate(filteredRecords, keyPath: \.timestamp), id: \.key) { section in
                                Section {
                                    ForEach(section.records) { r in
                                        feedingRow(r)
                                            .listRowBackground(Color.blCard)
                                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                            .contentShape(Rectangle())
                                            .onTapGesture { recordToEdit = r }
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button(role: .destructive) { recordToDelete = r } label: {
                                                    Label(String(localized: "track.delete"), systemImage: "trash")
                                                }
                                            }
                                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                                Button { recordToEdit = r } label: {
                                                    Label(String(localized: "track.edit"), systemImage: "pencil")
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
            }
        }
        .navigationTitle(String(localized: "allRecords.allFeedings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.blFeeding)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            FeedingLogView(vm: vm)
        }
        .sheet(item: $recordToEdit) { record in
            FeedingLogView(vm: vm, editingRecord: record)
        }
        .alert(String(localized: "allRecords.deleteRecord"), isPresented: Binding(
            get: { recordToDelete != nil },
            set: { if !$0 { recordToDelete = nil } }
        )) {
            Button(String(localized: "common.cancel"), role: .cancel) { recordToDelete = nil }
            Button(String(localized: "allRecords.delete"), role: .destructive) {
                Haptic.warning()
                if let obj = recordToDelete {
                    let success = vm.deleteObject(obj, in: ctx)
                    if success {
                        withAnimation { /* row removed */ }
                        appState.showToast(String(localized: "allRecords.feedingDeleted"), icon: "trash.fill", color: .blFeeding)
                    } else {
                        Haptic.error()
                        appState.showToast(String(localized: "common.deleteFailed"), icon: "exclamationmark.triangle.fill", color: .red)
                    }
                }
                recordToDelete = nil
            }
        } message: {
            Text(String(localized: "allRecords.deleteConfirmMsg"))
        }
    }

    private var feedingFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    label: String(localized: "allRecords.filterAll"),
                    count: records.count,
                    isSelected: selectedFilter == nil,
                    color: .blFeeding
                ) {
                    Haptic.selection()
                    withAnimation(.spring(response: 0.3)) { selectedFilter = nil }
                }
                ForEach(FeedType.allCases, id: \.self) { type in
                    let count = countFor(type)
                    if count > 0 {
                        FilterChip(
                            label: type.displayName,
                            count: count,
                            isSelected: selectedFilter == type,
                            color: .blFeeding
                        ) {
                            Haptic.selection()
                            withAnimation(.spring(response: 0.3)) {
                                selectedFilter = selectedFilter == type ? nil : type
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(Color.blBackground)
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
        let a11yLabel: String = {
            var parts = [feedType?.displayName ?? "Feeding"]
            if isOngoing {
                parts.append("in progress")
            } else if r.durationMinutes > 0 {
                parts.append(DurationFormat.standard(r.durationMinutes))
            }
            if r.amountML > 0 {
                let val = unit.volumeFromML(r.amountML)
                parts.append(unit == .metric
                    ? "\(Int(val)) \(unit.volumeLabel)"
                    : String(format: "%.1f %@", val, unit.volumeLabel))
            }
            if let side = r.breastSide, !side.isEmpty {
                parts.append(BreastSide(rawValue: side)?.displayName ?? side)
            }
            if let t = r.timestamp {
                parts.append("at \(t.formatted(date: .omitted, time: .shortened))")
            }
            if let notes = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                parts.append("note: \(notes)")
            }
            return parts.joined(separator: ", ")
        }()
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.blFeeding.opacity(isOngoing ? 0.25 : 0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: feedType?.icon ?? "drop.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.blFeeding)
                    .symbolEffect(.pulse, isActive: isOngoing)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(feedType?.displayName ?? "Feeding")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.blTextPrimary)
                    if isOngoing {
                        Text(String(localized: "allRecords.inProgress"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.blFeeding)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 8) {
                    if isOngoing {
                        Text(String(localized: "allRecords.timerRunning"))
                            .font(.system(size: 13))
                            .foregroundColor(.blFeeding)
                    } else if r.durationMinutes > 0 {
                        Text(DurationFormat.standard(r.durationMinutes))
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
                if let notes = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(NSLocalizedString("a11y.tapEditSwipeDelete", comment: ""))
    }
}

// MARK: - All Sleeps
struct AllSleepsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) var ctx
    @StateObject private var vm = TrackViewModel(context: PersistenceController.shared.container.viewContext)
    @State private var recordToDelete: CDSleepRecord?
    @State private var recordToEdit: CDSleepRecord?
    @State private var showAddSheet = false
    @State private var selectedFilter: SleepLocation? = nil

    @FetchRequest(
        entity: CDSleepRecord.entity(),
        sortDescriptors: [NSSortDescriptor(key: "startTime", ascending: false)]
    ) private var records: FetchedResults<CDSleepRecord>

    private var filteredRecords: [CDSleepRecord] {
        guard let filter = selectedFilter else { return Array(records) }
        return records.filter { SleepLocation(rawValue: $0.location ?? "") == filter }
    }

    /// Count of records for a given sleep location (for chip badge)
    private func countFor(_ location: SleepLocation) -> Int {
        records.filter { SleepLocation(rawValue: $0.location ?? "") == location }.count
    }

    var body: some View {
        ZStack {
            Color.blBackground.ignoresSafeArea()

            if records.isEmpty {
                emptyState(String(localized: "allRecords.noSleepsYet"), icon: "moon.zzz.fill", color: .blSleep)
            } else {
                VStack(spacing: 0) {
                    // Filter chips
                    sleepFilterBar

                    if filteredRecords.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 36))
                                .foregroundColor(.blSleep.opacity(0.4))
                            Text(String(localized: "allRecords.noFilteredSleeps \(selectedFilter?.displayName ?? "")"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.blTextSecondary)
                            Button {
                                withAnimation(.spring(response: 0.3)) { selectedFilter = nil }
                            } label: {
                                Text(String(localized: "allRecords.showAll"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.blSleep)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        List {
                            ForEach(groupedByDate(filteredRecords, keyPath: \.startTime), id: \.key) { section in
                                Section {
                                    ForEach(section.records) { r in
                                        sleepRow(r)
                                            .listRowBackground(Color.blCard)
                                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                            .contentShape(Rectangle())
                                            .onTapGesture { recordToEdit = r }
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button(role: .destructive) { recordToDelete = r } label: {
                                                    Label(String(localized: "track.delete"), systemImage: "trash")
                                                }
                                            }
                                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                                Button { recordToEdit = r } label: {
                                                    Label(String(localized: "track.edit"), systemImage: "pencil")
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
            }
        }
        .navigationTitle(String(localized: "allRecords.allSleep"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.blSleep)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            SleepLogView(vm: vm)
        }
        .sheet(item: $recordToEdit) { record in
            SleepLogView(vm: vm, editingRecord: record)
        }
        .alert(String(localized: "allRecords.deleteRecord"), isPresented: Binding(
            get: { recordToDelete != nil },
            set: { if !$0 { recordToDelete = nil } }
        )) {
            Button(String(localized: "common.cancel"), role: .cancel) { recordToDelete = nil }
            Button(String(localized: "allRecords.delete"), role: .destructive) {
                Haptic.warning()
                if let obj = recordToDelete {
                    let success = vm.deleteObject(obj, in: ctx)
                    if success {
                        withAnimation { /* row removed */ }
                        appState.showToast(String(localized: "allRecords.sleepDeleted"), icon: "trash.fill", color: .blSleep)
                    } else {
                        Haptic.error()
                        appState.showToast(String(localized: "common.deleteFailed"), icon: "exclamationmark.triangle.fill", color: .red)
                    }
                }
                recordToDelete = nil
            }
        } message: {
            Text(String(localized: "allRecords.deleteConfirmMsg"))
        }
    }

    private var sleepFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    label: String(localized: "allRecords.filterAll"),
                    count: records.count,
                    isSelected: selectedFilter == nil,
                    color: .blSleep
                ) {
                    Haptic.selection()
                    withAnimation(.spring(response: 0.3)) { selectedFilter = nil }
                }
                ForEach(SleepLocation.allCases, id: \.self) { location in
                    let count = countFor(location)
                    if count > 0 {
                        FilterChip(
                            label: location.displayName,
                            count: count,
                            isSelected: selectedFilter == location,
                            color: .blSleep
                        ) {
                            Haptic.selection()
                            withAnimation(.spring(response: 0.3)) {
                                selectedFilter = selectedFilter == location ? nil : location
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(Color.blBackground)
    }

    private func sleepRow(_ r: CDSleepRecord) -> some View {
        let locationName: String = {
            if let loc = r.location, let sl = SleepLocation(rawValue: loc) { return sl.displayName }
            return "Sleep"
        }()
        let a11yLabel: String = {
            var parts = [locationName]
            if let s = r.startTime, let e = r.endTime {
                let mins = Int(e.timeIntervalSince(s) / 60)
                let h = mins / 60, m = mins % 60
                parts.append(h > 0 ? "\(h) hours \(m) minutes" : "\(m) minutes")
                parts.append("\(s.formatted(date: .omitted, time: .shortened)) to \(e.formatted(date: .omitted, time: .shortened))")
            } else {
                parts.append("ongoing")
                if let s = r.startTime {
                    parts.append("started at \(s.formatted(date: .omitted, time: .shortened))")
                }
            }
            if let notes = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                parts.append("note: \(notes)")
            }
            return parts.joined(separator: ", ")
        }()
        return HStack(spacing: 12) {
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
                    Text(locationName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.blTextPrimary)

                    if let s = r.startTime, let e = r.endTime {
                        let mins = Int(e.timeIntervalSince(s) / 60)
                        Text(DurationFormat.fromMinutes(mins))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.blSleep)
                    } else {
                        Text(String(localized: "allRecords.ongoing"))
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

                if let notes = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundColor(.blTextTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(NSLocalizedString("a11y.tapEditSwipeDelete", comment: ""))
    }
}

// MARK: - All Diapers
struct AllDiapersView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) var ctx
    @StateObject private var vm = TrackViewModel(context: PersistenceController.shared.container.viewContext)
    @State private var recordToDelete: CDDiaperRecord?
    @State private var recordToEdit: CDDiaperRecord?
    @State private var showAddSheet = false
    @State private var selectedFilter: DiaperType? = nil

    @FetchRequest(
        entity: CDDiaperRecord.entity(),
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)]
    ) private var records: FetchedResults<CDDiaperRecord>

    private var filteredRecords: [CDDiaperRecord] {
        guard let filter = selectedFilter else { return Array(records) }
        return records.filter { DiaperType(rawValue: $0.diaperType ?? "") == filter }
    }

    private func countFor(_ type: DiaperType) -> Int {
        records.filter { DiaperType(rawValue: $0.diaperType ?? "") == type }.count
    }

    var body: some View {
        ZStack {
            Color.blBackground.ignoresSafeArea()

            if records.isEmpty {
                emptyState(String(localized: "allRecords.noDiapersYet"), icon: "oval.fill", color: .blDiaper)
            } else {
                VStack(spacing: 0) {
                    // Filter chips
                    diaperFilterBar

                    if filteredRecords.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 36))
                                .foregroundColor(.blDiaper.opacity(0.4))
                            Text(String(localized: "allRecords.noFilteredDiapers \(selectedFilter?.displayName ?? "")"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.blTextSecondary)
                            Button {
                                withAnimation(.spring(response: 0.3)) { selectedFilter = nil }
                            } label: {
                                Text(String(localized: "allRecords.showAll"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.blDiaper)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        List {
                            ForEach(groupedByDate(filteredRecords, keyPath: \.timestamp), id: \.key) { section in
                                Section {
                                    ForEach(section.records) { r in
                                        diaperRow(r)
                                            .listRowBackground(Color.blCard)
                                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                            .contentShape(Rectangle())
                                            .onTapGesture { recordToEdit = r }
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button(role: .destructive) { recordToDelete = r } label: {
                                                    Label(String(localized: "track.delete"), systemImage: "trash")
                                                }
                                            }
                                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                                Button { recordToEdit = r } label: {
                                                    Label(String(localized: "track.edit"), systemImage: "pencil")
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
            }
        }
        .navigationTitle(String(localized: "allRecords.allDiapers"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.blDiaper)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            DiaperLogView(vm: vm)
        }
        .sheet(item: $recordToEdit) { record in
            DiaperLogView(vm: vm, editingRecord: record)
        }
        .alert(String(localized: "allRecords.deleteRecord"), isPresented: Binding(
            get: { recordToDelete != nil },
            set: { if !$0 { recordToDelete = nil } }
        )) {
            Button(String(localized: "common.cancel"), role: .cancel) { recordToDelete = nil }
            Button(String(localized: "allRecords.delete"), role: .destructive) {
                Haptic.warning()
                if let obj = recordToDelete {
                    let success = vm.deleteObject(obj, in: ctx)
                    if success {
                        withAnimation { /* row removed */ }
                        appState.showToast(String(localized: "allRecords.diaperDeleted"), icon: "trash.fill", color: .blDiaper)
                    } else {
                        Haptic.error()
                        appState.showToast(String(localized: "common.deleteFailed"), icon: "exclamationmark.triangle.fill", color: .red)
                    }
                }
                recordToDelete = nil
            }
        } message: {
            Text(String(localized: "allRecords.deleteConfirmMsg"))
        }
    }

    private var diaperFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    label: String(localized: "allRecords.filterAll"),
                    count: records.count,
                    isSelected: selectedFilter == nil,
                    color: .blDiaper
                ) {
                    Haptic.selection()
                    withAnimation(.spring(response: 0.3)) { selectedFilter = nil }
                }
                ForEach(DiaperType.allCases, id: \.self) { type in
                    let count = countFor(type)
                    if count > 0 {
                        FilterChip(
                            label: type.displayName,
                            count: count,
                            isSelected: selectedFilter == type,
                            color: .blDiaper
                        ) {
                            Haptic.selection()
                            withAnimation(.spring(response: 0.3)) {
                                selectedFilter = selectedFilter == type ? nil : type
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(Color.blBackground)
    }

    private func diaperRow(_ r: CDDiaperRecord) -> some View {
        let diaperType = DiaperType(rawValue: r.diaperType ?? "")
        let a11yLabel: String = {
            var parts = ["\(diaperType?.displayName ?? "Diaper") diaper"]
            if let t = r.timestamp {
                parts.append("at \(t.formatted(date: .omitted, time: .shortened))")
            }
            if let notes = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                parts.append("note: \(notes)")
            }
            return parts.joined(separator: ", ")
        }()
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
                if let notes = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(NSLocalizedString("a11y.tapEditSwipeDelete", comment: ""))
    }
}

// MARK: - All Growth
struct AllGrowthView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) var ctx
    @StateObject private var vm = TrackViewModel(context: PersistenceController.shared.container.viewContext)
    @State private var recordToDelete: CDGrowthRecord?
    @State private var recordToEdit: CDGrowthRecord?
    @State private var showAddSheet = false

    @FetchRequest(
        entity: CDGrowthRecord.entity(),
        sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
    ) private var records: FetchedResults<CDGrowthRecord>

    var body: some View {
        ZStack {
            Color.blBackground.ignoresSafeArea()

            if records.isEmpty {
                emptyState(String(localized: "allRecords.noGrowthYet"), icon: "chart.bar.fill", color: .blGrowth)
            } else {
                List {
                    ForEach(groupedByDate(records, keyPath: \.date), id: \.key) { section in
                        Section {
                            ForEach(section.records) { r in
                                growthRow(r)
                                    .listRowBackground(Color.blCard)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .contentShape(Rectangle())
                                    .onTapGesture { recordToEdit = r }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) { recordToDelete = r } label: {
                                            Label(String(localized: "track.delete"), systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button { recordToEdit = r } label: {
                                            Label(String(localized: "track.edit"), systemImage: "pencil")
                                        }
                                        .tint(.blGrowth)
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
        .navigationTitle(String(localized: "allRecords.allGrowth"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.blGrowth)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            GrowthLogView(vm: vm)
        }
        .sheet(item: $recordToEdit) { record in
            GrowthLogView(vm: vm, editingRecord: record)
        }
        .alert(String(localized: "allRecords.deleteRecord"), isPresented: Binding(
            get: { recordToDelete != nil },
            set: { if !$0 { recordToDelete = nil } }
        )) {
            Button(String(localized: "common.cancel"), role: .cancel) { recordToDelete = nil }
            Button(String(localized: "allRecords.delete"), role: .destructive) {
                Haptic.warning()
                if let obj = recordToDelete {
                    let success = vm.deleteObject(obj, in: ctx)
                    if success {
                        withAnimation { /* row removed */ }
                        appState.showToast(String(localized: "allRecords.growthDeleted"), icon: "trash.fill", color: .blGrowth)
                    } else {
                        Haptic.error()
                        appState.showToast(String(localized: "common.deleteFailed"), icon: "exclamationmark.triangle.fill", color: .red)
                    }
                }
                recordToDelete = nil
            }
        } message: {
            Text(String(localized: "allRecords.deleteConfirmMsg"))
        }
    }

    private func growthRow(_ r: CDGrowthRecord) -> some View {
        let unit = appState.measurementUnit
        let baby = appState.currentBaby
        let a11yLabel: String = {
            var parts = ["Growth measurement"]
            if r.weightKG > 0 {
                parts.append(String(format: "weight %.2f %@", unit.weightFromKG(r.weightKG), unit.weightLabel))
            }
            if r.heightCM > 0 {
                parts.append(String(format: "height %.1f %@", unit.lengthFromCM(r.heightCM), unit.heightLabel))
            }
            if r.headCircumferenceCM > 0 {
                parts.append(String(format: "head %.1f %@", unit.lengthFromCM(r.headCircumferenceCM), unit.heightLabel))
            }
            if let baby, let date = r.date {
                parts.append(String(format: NSLocalizedString("a11y.atAge %@", comment: ""), baby.ageText(at: date)))
            }
            if let date = r.date {
                parts.append(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))
            }
            if let notes = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                parts.append("note: \(notes)")
            }
            return parts.joined(separator: ", ")
        }()
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.blGrowth.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.blGrowth)
            }

            VStack(alignment: .leading, spacing: 3) {
                // Compact measurement pills with icons for disambiguation
                HStack(spacing: 8) {
                    if r.weightKG > 0 {
                        growthMetricPill(
                            icon: "scalemass.fill",
                            text: String(format: "%.2f %@", unit.weightFromKG(r.weightKG), unit.weightLabel)
                        )
                    }
                    if r.heightCM > 0 {
                        growthMetricPill(
                            icon: "ruler.fill",
                            text: String(format: "%.1f %@", unit.lengthFromCM(r.heightCM), unit.heightLabel)
                        )
                    }
                    if r.headCircumferenceCM > 0 {
                        growthMetricPill(
                            icon: "circle.dashed",
                            text: String(format: "%.1f %@", unit.lengthFromCM(r.headCircumferenceCM), unit.heightLabel)
                        )
                    }
                }
                if let notes = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundColor(.blTextTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                // Baby's age at this measurement
                if let baby, let date = r.date {
                    Text(baby.ageText(at: date))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.blGrowth)
                }
                Text(r.date.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(.blTextTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(NSLocalizedString("a11y.tapEditSwipeDelete", comment: ""))
    }

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

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(isSelected ? color : .blTextTertiary)
            }
            .foregroundColor(isSelected ? .white : .blTextSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? color : Color.blSurface)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? color : Color.blSurface, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(format: NSLocalizedString("a11y.filterBadge %@ %lld", comment: ""), label, count))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Shared Helpers

private struct DateSection<T>: Identifiable {
    let key: String
    let records: [T]
    var id: String { key }
}

private func groupedByDate<T: NSManagedObject>(_ results: FetchedResults<T>, keyPath: KeyPath<T, Date?>) -> [DateSection<T>] {
    groupedByDate(Array(results), keyPath: keyPath)
}

private func groupedByDate<T: NSManagedObject>(_ items: [T], keyPath: KeyPath<T, Date?>) -> [DateSection<T>] {
    let cal = Calendar.current
    var dict: [String: [T]] = [:]
    var order: [String] = []

    for record in items {
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
