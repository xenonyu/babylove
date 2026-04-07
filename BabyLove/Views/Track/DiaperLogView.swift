import SwiftUI
import CoreData

struct DiaperLogView: View {
    @ObservedObject var vm: TrackViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    /// UserDefaults key for persisting the last-used diaper type across sessions
    private static let lastDiaperTypeKey = "lastDiaperType"

    /// When non-nil, we are editing an existing record
    var editingRecord: CDDiaperRecord?
    /// Optional initial date for the timestamp (used for retroactive logging from past dates)
    var initialDate: Date? = nil

    @State private var diaperType: DiaperType = .wet
    @State private var notes = ""
    @State private var timestamp = Date()
    @State private var showTimePicker = false
    /// Guards against double-tap creating duplicate records
    @State private var isSaving = false
    /// Today's diaper stats for the context badge
    @State private var todayDiaperStats: TodayDiaperStats = .empty
    /// Whether the current timestamp falls on a different calendar day than today
    private var isTimestampPastDay: Bool {
        !Calendar.current.isDateInToday(timestamp)
    }

    private var isEditing: Bool { editingRecord != nil }

    /// Whether the form has meaningful user input that would be lost on dismiss.
    private var hasUnsavedChanges: Bool {
        if isEditing { return true }
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }

    // MARK: - Today's Diaper Stats

    /// Lightweight struct holding today's diaper breakdown
    struct TodayDiaperStats {
        let total: Int
        let wet: Int
        let dirty: Int
        let lastChangeDate: Date?

        static let empty = TodayDiaperStats(total: 0, wet: 0, dirty: 0, lastChangeDate: nil)
    }

    /// Fetch today's diaper records and compute the breakdown.
    private func loadTodayStats() {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<CDDiaperRecord> = CDDiaperRecord.fetchRequest()
        let startOfDay = Calendar.current.startOfDay(for: Date()) as NSDate
        req.predicate = NSPredicate(format: "timestamp >= %@", startOfDay)
        guard let results = try? ctx.fetch(req) else { return }
        var wet = 0, dirty = 0
        for r in results {
            switch DiaperType(rawValue: r.diaperType ?? "") {
            case .wet:   wet += 1
            case .dirty: dirty += 1
            case .both:  wet += 1; dirty += 1
            case .dry, .none: break
            }
        }
        // Fetch most recent diaper change globally (not limited to today)
        let lastReq: NSFetchRequest<CDDiaperRecord> = CDDiaperRecord.fetchRequest()
        lastReq.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        lastReq.fetchLimit = 1
        let lastDate = (try? ctx.fetch(lastReq))?.first?.timestamp
        todayDiaperStats = TodayDiaperStats(total: results.count, wet: wet, dirty: dirty, lastChangeDate: lastDate)
    }

    /// Short "time since" text reusing shared localization keys.
    private static func timeSinceText(from date: Date?) -> String? {
        guard let date else { return nil }
        let seconds = Int(Date().timeIntervalSince(date))
        guard seconds >= 0 else { return nil }
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

    /// The context badge showing today's diaper count with wet/dirty breakdown
    @ViewBuilder
    private var todayContextBadge: some View {
        if !isEditing && todayDiaperStats.total > 0 {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.blDiaper)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: NSLocalizedString("diaperLog.todayCount %lld", comment: ""), todayDiaperStats.total))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blTextPrimary)
                    HStack(spacing: 8) {
                        if todayDiaperStats.wet > 0 {
                            Text("💧 \(todayDiaperStats.wet)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.blTextSecondary)
                        }
                        if todayDiaperStats.dirty > 0 {
                            Text("💩 \(todayDiaperStats.dirty)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.blTextSecondary)
                        }
                        if let ts = Self.timeSinceText(from: todayDiaperStats.lastChangeDate) {
                            Text("⏱ \(ts)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.blTextSecondary)
                        }
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(Color.blDiaper.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel({
                var label = String(format: NSLocalizedString("a11y.diaperTodayCount %lld %lld %lld", comment: ""), todayDiaperStats.total, todayDiaperStats.wet, todayDiaperStats.dirty)
                if let ts = Self.timeSinceText(from: todayDiaperStats.lastChangeDate) {
                    label += ", \(ts)"
                }
                return label
            }())
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        // Today's diaper context (only for new records)
                        todayContextBadge

                        // Retroactive date banner — shown when creating a new record for a past day
                        // Suppressed when editing, since the timestamp already belongs to the record
                        if isTimestampPastDay && !isEditing {
                            HStack(spacing: 10) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 16))
                                    .foregroundColor(.blDiaper)
                                Text(String(format: NSLocalizedString("log.recordingFor %@", comment: ""), timestamp.formatted(date: .long, time: .omitted)))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.blTextPrimary)
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.blDiaper.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.blDiaper.opacity(0.2), lineWidth: 1)
                            )
                        }

                        // Type selection
                        VStack(alignment: .leading, spacing: 14) {
                            Text(NSLocalizedString("diaperLog.diaperType", comment: ""))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                                ForEach(DiaperType.allCases, id: \.self) { t in
                                    Button {
                                        Haptic.selection()
                                        withAnimation(.spring(response: 0.3)) { diaperType = t }
                                    } label: {
                                        VStack(spacing: 10) {
                                            Text(t.icon)
                                                .font(.system(size: 36))
                                            Text(t.displayName)
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(diaperType == t ? .white : .blTextPrimary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 100)
                                        .background(diaperType == t ? Color.blDiaper : Color.blSurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(String(format: NSLocalizedString("a11y.diaperTypeOption %@", comment: ""), t.displayName))
                                    .accessibilityAddTraits(diaperType == t ? .isSelected : [])
                                }
                            }
                        }

                        // Time
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                withAnimation(.spring(response: 0.3)) { showTimePicker.toggle() }
                            } label: {
                                HStack {
                                    Label(NSLocalizedString("log.time", comment: ""), systemImage: "clock.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.blTextSecondary)
                                    Spacer()
                                    // Show date + time when recording to a past day
                                    Text(isTimestampPastDay
                                         ? timestamp.formatted(date: .abbreviated, time: .shortened)
                                         : timestamp.formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.blDiaper)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.blTextTertiary)
                                        .rotationEffect(.degrees(showTimePicker ? 90 : 0))
                                }
                                .padding(14)
                                .background(Color.blSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            if showTimePicker {
                                DatePicker("Diaper change time", selection: $timestamp, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .tint(.blDiaper)
                                    .labelsHidden()
                                    .accessibilityLabel(NSLocalizedString("a11y.diaperChangeTime", comment: ""))
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }

                        // Notes with quick-suggestion chips
                        VStack(alignment: .leading, spacing: 10) {
                            Label(NSLocalizedString("log.notesOptional", comment: ""), systemImage: "note.text")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)

                            // Quick-note suggestion chips — tap to append to notes
                            quickNoteChips

                            TextField(NSLocalizedString("diaperLog.notesPlaceholder", comment: ""), text: $notes, axis: .vertical)
                                .lineLimit(2...4)
                                .padding(14)
                                .background(Color.blSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Button(isEditing
                               ? NSLocalizedString("diaperLog.updateDiaper", comment: "")
                               : NSLocalizedString("diaperLog.logDiaper", comment: "")) {
                            guard !isSaving else { return }
                            isSaving = true
                            var ok = false
                            if let record = editingRecord {
                                ok = vm.updateDiaper(record, type: diaperType, notes: notes, timestamp: timestamp)
                                appState.showToast(ok ? NSLocalizedString("diaperLog.updated", comment: "") : NSLocalizedString("diaperLog.saveFailed", comment: ""),
                                                   icon: ok ? "pencil.circle.fill" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blDiaper : .red)
                            } else {
                                ok = vm.logDiaper(type: diaperType, notes: notes, timestamp: timestamp)
                                appState.showToast(ok ? NSLocalizedString("diaperLog.logged", comment: "") : NSLocalizedString("diaperLog.saveFailed", comment: ""),
                                                   icon: ok ? "oval.fill" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blDiaper : .red)
                            }
                            if ok { Self.saveLastDiaperType(diaperType); Haptic.success(); dismiss() } else { Haptic.error(); isSaving = false }
                        }
                        .buttonStyle(BLPrimaryButton(color: .blDiaper))
                        .disabled(isSaving)
                        .padding(.top, 8)
                    }
                    .padding(24)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? NSLocalizedString("diaperLog.editTitle", comment: "") : NSLocalizedString("diaperLog.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("log.cancel", comment: "")) { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(NSLocalizedString("log.done", comment: "")) {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blDiaper)
                }
            }
            .onAppear {
                populateFromRecord()
                // Restore last-used diaper type for new records only
                if !isEditing { restoreLastDiaperType() }
                // Apply initial date for retroactive logging (only when creating new records)
                if !isEditing, let initialDate {
                    timestamp = initialDate
                }
                // Load today's diaper stats for context badge
                loadTodayStats()
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
        }
    }

    // MARK: - Quick Note Suggestions

    /// Common diaper observations that parents frequently note.
    /// Contextual: some chips only appear for specific diaper types.
    private var quickNoteSuggestions: [String] {
        var suggestions: [String] = []
        switch diaperType {
        case .wet:
            suggestions = [
                NSLocalizedString("diaperLog.chip.lightWet", comment: ""),
                NSLocalizedString("diaperLog.chip.heavyWet", comment: ""),
                NSLocalizedString("diaperLog.chip.rash", comment: ""),
                NSLocalizedString("diaperLog.chip.leakage", comment: ""),
            ]
        case .dirty:
            suggestions = [
                NSLocalizedString("diaperLog.chip.soft", comment: ""),
                NSLocalizedString("diaperLog.chip.loose", comment: ""),
                NSLocalizedString("diaperLog.chip.firm", comment: ""),
                NSLocalizedString("diaperLog.chip.greenish", comment: ""),
                NSLocalizedString("diaperLog.chip.rash", comment: ""),
            ]
        case .both:
            suggestions = [
                NSLocalizedString("diaperLog.chip.loose", comment: ""),
                NSLocalizedString("diaperLog.chip.rash", comment: ""),
                NSLocalizedString("diaperLog.chip.heavyWet", comment: ""),
                NSLocalizedString("diaperLog.chip.greenish", comment: ""),
            ]
        case .dry:
            suggestions = [
                NSLocalizedString("diaperLog.chip.rash", comment: ""),
                NSLocalizedString("diaperLog.chip.creamApplied", comment: ""),
            ]
        }
        return suggestions
    }

    /// Whether a suggestion chip's text is already contained in the notes field
    private func chipAlreadyAdded(_ chip: String) -> Bool {
        notes.localizedCaseInsensitiveContains(chip)
    }

    private var quickNoteChips: some View {
        // Use a flowing layout via HStack + wrapping
        FlowLayout(spacing: 8) {
            ForEach(quickNoteSuggestions, id: \.self) { chip in
                let isAdded = chipAlreadyAdded(chip)
                Button {
                    Haptic.selection()
                    if isAdded {
                        // Remove chip text from notes
                        removeChipFromNotes(chip)
                    } else {
                        // Append chip text to notes
                        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            notes = chip
                        } else {
                            notes += ", \(chip)"
                        }
                    }
                } label: {
                    Text(chip)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isAdded ? .white : .blDiaper)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isAdded ? Color.blDiaper : Color.blDiaper.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(chip)
                .accessibilityAddTraits(isAdded ? .isSelected : [])
            }
        }
    }

    /// Remove a chip's text from the notes field, cleaning up surrounding separators
    private func removeChipFromNotes(_ chip: String) {
        // Try to remove ", chip" or "chip, " or just "chip"
        if let range = notes.range(of: ", \(chip)", options: .caseInsensitive) {
            notes.removeSubrange(range)
        } else if let range = notes.range(of: "\(chip), ", options: .caseInsensitive) {
            notes.removeSubrange(range)
        } else if let range = notes.range(of: chip, options: .caseInsensitive) {
            notes.removeSubrange(range)
        }
        notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        // Clean up trailing/leading separators
        if notes.hasPrefix(", ") { notes = String(notes.dropFirst(2)) }
        if notes.hasSuffix(",") { notes = String(notes.dropLast()) }
        notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func populateFromRecord() {
        guard let r = editingRecord else { return }
        diaperType = DiaperType(rawValue: r.diaperType ?? "") ?? .wet
        notes = r.notes ?? ""
        timestamp = r.timestamp ?? Date()
    }

    // MARK: - Remember Last Diaper Type

    /// Restore the last-used diaper type so the user doesn't have to re-select every time.
    /// Only applied for new records — editing always uses the record's own diaper type.
    private func restoreLastDiaperType() {
        guard let raw = UserDefaults.standard.string(forKey: Self.lastDiaperTypeKey),
              let saved = DiaperType(rawValue: raw) else { return }
        diaperType = saved
    }

    /// Persist the selected diaper type for next time.
    private static func saveLastDiaperType(_ type: DiaperType) {
        UserDefaults.standard.set(type.rawValue, forKey: lastDiaperTypeKey)
    }
}
