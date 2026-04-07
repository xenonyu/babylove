import SwiftUI
import CoreData

struct SleepLogView: View {
    @ObservedObject var vm: TrackViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    /// When non-nil, we are editing an existing record
    var editingRecord: CDSleepRecord?
    /// Optional initial date for the timestamp (used for retroactive logging from past dates)
    var initialDate: Date? = nil

    @State private var startTime = Date().addingTimeInterval(-3600)
    @State private var endTime   = Date()
    @State private var location: SleepLocation = .crib

    /// UserDefaults key for remembering the last-used sleep location
    private static let lastLocationKey = "lastSleepLocation"
    @State private var notes = ""
    @State private var isOngoing = false
    /// True when another sleep timer is already running (prevents duplicates)
    @State private var hasExistingOngoingSleep = false
    /// Timer that keeps the displayed ongoing duration up to date
    @State private var elapsedTimer: Timer?
    /// Guards against double-tap creating duplicate records
    @State private var isSaving = false
    /// Whether the start time falls on a different calendar day than today
    private var isStartTimePastDay: Bool {
        !Calendar.current.isDateInToday(startTime)
    }

    private var isEditing: Bool { editingRecord != nil }

    /// Whether the form has meaningful user input that would be lost on dismiss.
    private var hasUnsavedChanges: Bool {
        if isEditing { return true }
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }

    /// Whether the form is valid for saving:
    /// - Ongoing mode: valid only if no other sleep timer is already running
    /// - Finished mode: endTime must be after startTime (duration > 0)
    private var canSave: Bool {
        if isOngoing {
            // Allow editing an existing ongoing record, but block creating a new one
            // when another timer is already running
            return isEditing || !hasExistingOngoingSleep
        }
        return duration > 0
    }

    private var duration: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }
    private var durationText: String {
        DurationFormat.fromMinutes(duration)
    }
    /// Elapsed minutes for the ongoing sleep, updated by `elapsedTimer`.
    @State private var ongoingElapsedMinutes: Int = 0

    private var ongoingDurationText: String {
        // Reference the state var so SwiftUI triggers re-render when it changes
        let mins = ongoingElapsedMinutes
        return DurationFormat.fromMinutes(mins)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {

                        // Retroactive date banner — shown when logging to a past day
                        if isStartTimePastDay && !isEditing {
                            HStack(spacing: 10) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 16))
                                    .foregroundColor(.blSleep)
                                Text(String(format: NSLocalizedString("log.recordingFor %@", comment: ""), startTime.formatted(date: .long, time: .omitted)))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.blTextPrimary)
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.blSleep.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.blSleep.opacity(0.2), lineWidth: 1)
                            )
                        }

                        // Ongoing toggle
                        Toggle(isOn: $isOngoing) {
                            Label(isEditing
                                  ? NSLocalizedString("sleepLog.stillSleeping", comment: "")
                                  : NSLocalizedString("sleepLog.babyIsSleeping", comment: ""),
                                  systemImage: "moon.zzz.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextPrimary)
                        }
                        .tint(.blSleep)
                        .padding(16)
                        .background(Color.blSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        // Warning: another sleep timer already running
                        if isOngoing && hasExistingOngoingSleep && !isEditing {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.blGrowth)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(NSLocalizedString("sleepLog.timerRunning", comment: ""))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.blTextPrimary)
                                    Text(NSLocalizedString("sleepLog.timerRunningHint", comment: ""))
                                        .font(.system(size: 13))
                                        .foregroundColor(.blTextSecondary)
                                }
                            }
                            .padding(14)
                            .background(Color.blGrowth.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.blGrowth.opacity(0.3), lineWidth: 1)
                            )
                        }

                        if isOngoing {
                            // Ongoing: show start time + live elapsed
                            VStack(alignment: .leading, spacing: 10) {
                                Label(NSLocalizedString("sleepLog.fellAsleep", comment: ""), systemImage: "moon.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.blTextSecondary)
                                DatePicker("Fell asleep time", selection: $startTime, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .tint(.blSleep)
                                    .labelsHidden()
                                    .accessibilityLabel(NSLocalizedString("a11y.fellAsleepTime", comment: ""))
                            }

                            if isEditing {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 4) {
                                        Text(ongoingDurationText)
                                            .font(.system(size: 36, weight: .bold))
                                            .foregroundColor(.blSleep)
                                        Text(NSLocalizedString("sleepLog.sleeping", comment: ""))
                                            .font(.system(size: 14))
                                            .foregroundColor(.blTextSecondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                        } else {
                            // Finished: show duration + start/end pickers
                            HStack {
                                Spacer()
                                VStack(spacing: 4) {
                                    Text(durationText)
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundColor(.blSleep)
                                    Text(NSLocalizedString("sleepLog.sleepDuration", comment: ""))
                                        .font(.system(size: 14))
                                        .foregroundColor(.blTextSecondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)

                            // Start time
                            VStack(alignment: .leading, spacing: 10) {
                                Label(NSLocalizedString("sleepLog.startTime", comment: ""), systemImage: "moon.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.blTextSecondary)
                                DatePicker("Sleep start time", selection: $startTime, in: ...endTime, displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .tint(.blSleep)
                                    .labelsHidden()
                                    .accessibilityLabel(NSLocalizedString("a11y.sleepStartTime", comment: ""))
                            }

                            // End time
                            VStack(alignment: .leading, spacing: 10) {
                                Label(NSLocalizedString("sleepLog.wakeTime", comment: ""), systemImage: "sun.and.horizon.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.blTextSecondary)
                                DatePicker("Wake up time", selection: $endTime, in: startTime...Date(), displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .tint(.blSleep)
                                    .labelsHidden()
                                    .accessibilityLabel(NSLocalizedString("a11y.wakeUpTime", comment: ""))
                            }
                        }

                        // Location
                        VStack(alignment: .leading, spacing: 10) {
                            Label(NSLocalizedString("sleepLog.location", comment: ""), systemImage: "location.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(SleepLocation.allCases, id: \.self) { loc in
                                    Button {
                                        Haptic.selection()
                                        withAnimation(.spring(response: 0.3)) { location = loc }
                                    } label: {
                                        VStack(spacing: 4) {
                                            Text(loc.icon).font(.system(size: 22))
                                            Text(loc.displayName)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(location == loc ? .white : .blTextPrimary)
                                                .multilineTextAlignment(.center)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(location == loc ? Color.blSleep : Color.blSurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(loc.displayName)
                                    .accessibilityAddTraits(location == loc ? .isSelected : [])
                                }
                            }
                        }

                        // Notes with quick-suggestion chips
                        VStack(alignment: .leading, spacing: 10) {
                            Label(NSLocalizedString("log.notes", comment: ""), systemImage: "note.text")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)

                            // Quick-note suggestion chips — tap to append to notes
                            sleepNoteChips

                            TextField(NSLocalizedString("log.addNote", comment: ""), text: $notes, axis: .vertical)
                                .lineLimit(2...4)
                                .padding(14)
                                .background(Color.blSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Button(isEditing
                               ? NSLocalizedString("sleepLog.updateSleep", comment: "")
                               : (isOngoing
                                  ? NSLocalizedString("sleepLog.startTimer", comment: "")
                                  : NSLocalizedString("sleepLog.logSleep", comment: ""))) {
                            guard !isSaving else { return }
                            isSaving = true
                            var ok = false
                            if let record = editingRecord {
                                ok = vm.updateSleep(record, start: startTime, end: isOngoing ? nil : endTime, location: location, notes: notes)
                                appState.showToast(ok ? NSLocalizedString("sleepLog.updated", comment: "") : NSLocalizedString("sleepLog.saveFailed", comment: ""),
                                                   icon: ok ? "pencil.circle.fill" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blSleep : .red)
                            } else if isOngoing {
                                ok = vm.startSleep(at: startTime, location: location, notes: notes)
                                appState.showToast(ok ? NSLocalizedString("sleepLog.timerStarted", comment: "") : NSLocalizedString("sleepLog.saveFailed", comment: ""),
                                                   icon: ok ? "moon.zzz.fill" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blSleep : .red)
                            } else {
                                ok = vm.logSleep(start: startTime, end: endTime, location: location, notes: notes)
                                appState.showToast(ok ? NSLocalizedString("sleepLog.logged", comment: "") : NSLocalizedString("sleepLog.saveFailed", comment: ""),
                                                   icon: ok ? "moon.zzz.fill" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blSleep : .red)
                            }
                            if ok {
                                Self.saveLastLocation(location)
                                Haptic.success()
                                dismiss()
                            } else { Haptic.error(); isSaving = false }
                        }
                        .buttonStyle(BLPrimaryButton(color: .blSleep))
                        .disabled(!canSave || isSaving)
                        .opacity(canSave && !isSaving ? 1 : 0.5)
                        .padding(.top, 8)

                        if !canSave && isOngoing && hasExistingOngoingSleep && !isEditing {
                            Text(NSLocalizedString("sleepLog.timerActive", comment: ""))
                                .font(.system(size: 13))
                                .foregroundColor(.blGrowth)
                                .frame(maxWidth: .infinity)
                        } else if !canSave && !isOngoing {
                            Text(NSLocalizedString("sleepLog.endAfterStart", comment: ""))
                                .font(.system(size: 13))
                                .foregroundColor(.blTextSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(24)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? NSLocalizedString("sleepLog.editTitle", comment: "") : NSLocalizedString("sleepLog.title", comment: ""))
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
                    .foregroundColor(.blSleep)
                }
            }
            .onAppear {
                populateFromRecord()
                // Apply initial date for retroactive logging (only when creating new records)
                if !isEditing, let initialDate {
                    startTime = initialDate.addingTimeInterval(-3600)
                    endTime = initialDate
                }
                if !isEditing { restoreLastLocation() }
                checkExistingOngoingSleep()
                updateOngoingElapsed()
                startElapsedTimerIfNeeded()
            }
            .onDisappear {
                elapsedTimer?.invalidate()
                elapsedTimer = nil
            }
            .onChange(of: isOngoing) { oldValue, newValue in
                // When toggling from ongoing → finished, snap endTime to now
                if oldValue == true && newValue == false {
                    endTime = Date()
                    elapsedTimer?.invalidate()
                    elapsedTimer = nil
                } else if oldValue == false && newValue == true {
                    updateOngoingElapsed()
                    startElapsedTimerIfNeeded()
                }
            }
            .onChange(of: startTime) { _, _ in
                updateOngoingElapsed()
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
        }
    }

    /// Recalculate the displayed elapsed minutes from the current startTime.
    private func updateOngoingElapsed() {
        ongoingElapsedMinutes = max(0, Int(Date().timeIntervalSince(startTime) / 60))
    }

    /// Start a 15-second timer that keeps the displayed ongoing duration fresh.
    private func startElapsedTimerIfNeeded() {
        guard isOngoing, elapsedTimer == nil else { return }
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { @MainActor in
                updateOngoingElapsed()
            }
        }
    }

    /// Check if another sleep record is already ongoing (endTime == nil).
    /// Excludes the record being edited (if any) to allow editing an ongoing sleep.
    private func checkExistingOngoingSleep() {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<CDSleepRecord> = CDSleepRecord.fetchRequest()
        req.predicate = NSPredicate(format: "endTime == nil")
        // When editing, we need to fetch at least 2 results so that if the first
        // result is the record being edited, we can still detect a second ongoing
        // sleep. With fetchLimit=1 the duplicate could be masked.
        req.fetchLimit = isEditing ? 2 : 1
        guard let results = try? ctx.fetch(req) else { return }
        // If editing an ongoing sleep, that record itself shouldn't count
        if let editing = editingRecord {
            hasExistingOngoingSleep = results.contains(where: { $0.objectID != editing.objectID })
        } else {
            hasExistingOngoingSleep = !results.isEmpty
        }
    }

    // MARK: - Quick Note Suggestions

    /// Common sleep observations. Contextual: chips differ between
    /// ongoing (start-of-sleep) and finished (post-sleep) modes.
    private var sleepNoteSuggestions: [String] {
        if isOngoing {
            return [
                NSLocalizedString("sleepLog.chip.fussy", comment: ""),
                NSLocalizedString("sleepLog.chip.fedToSleep", comment: ""),
                NSLocalizedString("sleepLog.chip.rockedToSleep", comment: ""),
                NSLocalizedString("sleepLog.chip.selfSoothed", comment: ""),
            ]
        } else {
            return [
                NSLocalizedString("sleepLog.chip.wokeOnce", comment: ""),
                NSLocalizedString("sleepLog.chip.wokeCrying", comment: ""),
                NSLocalizedString("sleepLog.chip.restless", comment: ""),
                NSLocalizedString("sleepLog.chip.sleptWell", comment: ""),
                NSLocalizedString("sleepLog.chip.nightFeed", comment: ""),
            ]
        }
    }

    /// Whether a suggestion chip's text is already contained in the notes field
    private func chipAlreadyAdded(_ chip: String) -> Bool {
        notes.localizedCaseInsensitiveContains(chip)
    }

    private var sleepNoteChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(sleepNoteSuggestions, id: \.self) { chip in
                let isAdded = chipAlreadyAdded(chip)
                Button {
                    Haptic.selection()
                    if isAdded {
                        removeChipFromNotes(chip)
                    } else {
                        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            notes = chip
                        } else {
                            notes += ", \(chip)"
                        }
                    }
                } label: {
                    Text(chip)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isAdded ? .white : .blSleep)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isAdded ? Color.blSleep : Color.blSleep.opacity(0.1))
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
        if let range = notes.range(of: ", \(chip)", options: .caseInsensitive) {
            notes.removeSubrange(range)
        } else if let range = notes.range(of: "\(chip), ", options: .caseInsensitive) {
            notes.removeSubrange(range)
        } else if let range = notes.range(of: chip, options: .caseInsensitive) {
            notes.removeSubrange(range)
        }
        notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.hasPrefix(", ") { notes = String(notes.dropFirst(2)) }
        if notes.hasSuffix(",") { notes = String(notes.dropLast()) }
        notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func populateFromRecord() {
        guard let r = editingRecord else { return }
        startTime = r.startTime ?? Date().addingTimeInterval(-3600)
        endTime = r.endTime ?? Date()
        location = SleepLocation(rawValue: r.location ?? "") ?? .crib
        notes = r.notes ?? ""
        isOngoing = (r.endTime == nil)
    }

    // MARK: - Remember Last Sleep Location

    /// Restore the last-used sleep location so the user doesn't have to re-select every time.
    private func restoreLastLocation() {
        guard let raw = UserDefaults.standard.string(forKey: Self.lastLocationKey),
              let saved = SleepLocation(rawValue: raw) else { return }
        location = saved
    }

    /// Persist the selected sleep location for next time.
    private static func saveLastLocation(_ loc: SleepLocation) {
        UserDefaults.standard.set(loc.rawValue, forKey: lastLocationKey)
    }
}
