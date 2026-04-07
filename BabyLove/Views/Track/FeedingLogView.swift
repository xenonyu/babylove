import SwiftUI
import CoreData

struct FeedingLogView: View {
    @ObservedObject var vm: TrackViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    /// When non-nil, we are editing an existing record
    var editingRecord: CDFeedingRecord?
    /// Optional initial date for the timestamp (used for retroactive logging from past dates)
    var initialDate: Date? = nil

    @State private var feedType: FeedType = .breast

    /// UserDefaults key for remembering the last-used feed type
    private static let lastFeedTypeKey = "lastFeedType"
    @State private var side: BreastSide = .left
    @State private var duration: Double = 10
    @State private var amount: Double = 0
    @State private var notes = ""
    @State private var timestamp = Date()
    @State private var showTimePicker = false
    /// True when this log view was opened for a past date (retroactive logging)
    private var isRetroactive: Bool { initialDate != nil }
    /// Whether the current timestamp falls on a different calendar day than today
    private var isTimestampPastDay: Bool {
        !Calendar.current.isDateInToday(timestamp)
    }
    @State private var isTimerMode = false
    @State private var lastSideUsed: BreastSide?
    @State private var didAutoSuggestSide = false
    /// True when another feeding timer is already running (prevents duplicates)
    @State private var hasExistingOngoingFeeding = false
    /// True when editing an ongoing (timer) feeding — lets user finalize duration
    @State private var isEditingOngoingFeeding = false
    /// Timer to keep the displayed elapsed duration up to date while editing an ongoing feeding
    @State private var elapsedTimer: Timer?
    /// Guards against double-tap creating duplicate records
    @State private var isSaving = false

    private var isEditing: Bool { editingRecord != nil }
    private var unit: MeasurementUnit { appState.measurementUnit }
    /// Max amount in display unit (300 ml ~ 10 oz)
    private var maxAmount: Double { unit == .metric ? 300 : 10 }
    private var amountStep: Double { unit == .metric ? 5 : 0.5 }

    /// Localized human-readable duration (e.g. "15 min", "1h 30m", "1時間30分")
    private var durationDisplayText: String {
        DurationFormat.standard(Int16(duration))
    }

    /// Accessibility-friendly duration text (locale-aware for VoiceOver)
    private static let a11yDurationFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.unitsStyle = .full  // "2 hours 15 minutes" / "2時間15分" / "2시간 15분"
        f.allowedUnits = [.hour, .minute]
        f.zeroFormattingBehavior = .dropAll
        return f
    }()

    private var durationAccessibilityText: String {
        let seconds = TimeInterval(duration) * 60
        return Self.a11yDurationFormatter.string(from: seconds) ?? "\(Int(duration))m"
    }

    /// Locale-aware volume text for VoiceOver (e.g. "120 milliliters" / "120 ミリリットル")
    private static let a11yMLFormatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitStyle = .long
        f.unitOptions = .providedUnit
        f.numberFormatter.maximumFractionDigits = 0
        return f
    }()
    private static let a11yOzFormatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitStyle = .long
        f.unitOptions = .providedUnit
        f.numberFormatter.maximumFractionDigits = 1
        return f
    }()

    private static func accessibilityVolumeText(amount: Double, unit: MeasurementUnit) -> String {
        if unit == .metric {
            let m = Measurement(value: amount, unit: UnitVolume.milliliters)
            return a11yMLFormatter.string(from: m)
        } else {
            let m = Measurement(value: amount, unit: UnitVolume.fluidOunces)
            return a11yOzFormatter.string(from: m)
        }
    }

    /// Whether the current feed type supports timer mode
    private var supportsTimer: Bool {
        feedType == .breast || feedType == .pump
    }

    /// Dynamic button label based on mode
    private var buttonLabel: String {
        if isEditingOngoingFeeding { return NSLocalizedString("feedLog.endFeeding", comment: "") }
        if isEditing { return NSLocalizedString("feedLog.updateFeeding", comment: "") }
        if isTimerMode && supportsTimer { return NSLocalizedString("feedLog.startTimer", comment: "") }
        return NSLocalizedString("feedLog.logFeeding", comment: "")
    }

    /// Whether the form has meaningful user input that would be lost on dismiss.
    /// Used to prevent accidental swipe-to-dismiss on the sheet.
    private var hasUnsavedChanges: Bool {
        if isEditing { return true }
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if (feedType == .formula || feedType == .solid) && amount > 0 { return true }
        return false
    }

    /// Formula/solid require amount > 0; breast/pump always valid (have duration).
    /// Timer mode is blocked when another feeding timer is already running.
    private var canSave: Bool {
        if isTimerMode && supportsTimer && !isEditing && hasExistingOngoingFeeding {
            return false
        }
        switch feedType {
        case .formula, .solid: return amount > 0
        case .breast, .pump:   return true
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {

                        // Retroactive date banner — shown when creating a new record for a past day
                        // Suppressed when editing, since the timestamp already belongs to the record
                        if isTimestampPastDay && !isEditing {
                            HStack(spacing: 10) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 16))
                                    .foregroundColor(.blFeeding)
                                Text(String(format: NSLocalizedString("log.recordingFor %@", comment: ""), timestamp.formatted(date: .long, time: .omitted)))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.blTextPrimary)
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.blFeeding.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.blFeeding.opacity(0.2), lineWidth: 1)
                            )
                        }

                        // Feed type picker
                        VStack(alignment: .leading, spacing: 10) {
                            Label(NSLocalizedString("feedLog.type", comment: ""), systemImage: "drop.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                            HStack(spacing: 10) {
                                ForEach(FeedType.allCases, id: \.self) { t in
                                    Button {
                                        Haptic.selection()
                                        withAnimation(.spring(response: 0.3)) { feedType = t }
                                    } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: t.icon)
                                                .font(.system(size: 20))
                                                .foregroundColor(feedType == t ? .white : .blFeeding)
                                            Text(t.displayName)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(feedType == t ? .white : .blTextPrimary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(feedType == t ? Color.blFeeding : Color.blSurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(String(format: NSLocalizedString("a11y.feedTypeOption %@", comment: ""), t.displayName))
                                    .accessibilityAddTraits(feedType == t ? .isSelected : [])
                                }
                            }
                        }

                        // Breast side (when breast)
                        if feedType == .breast || feedType == .pump {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(NSLocalizedString("feedLog.side", comment: ""), systemImage: "arrow.left.arrow.right")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.blTextSecondary)
                                HStack(spacing: 10) {
                                    ForEach(BreastSide.allCases, id: \.self) { s in
                                        Button {
                                            Haptic.selection()
                                            withAnimation(.spring(response: 0.3)) { side = s }
                                        } label: {
                                            Text(s.displayName)
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(side == s ? .white : .blTextPrimary)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(side == s ? Color.blFeeding : Color.blSurface)
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(String(format: NSLocalizedString("a11y.breastSideOption %@", comment: ""), s.displayName))
                                        .accessibilityAddTraits(side == s ? .isSelected : [])
                                    }
                                }

                                // Smart side suggestion hint
                                if !isEditing, let lastSide = lastSideUsed, lastSide != .both {
                                    HStack(spacing: 6) {
                                        Image(systemName: "brain.head.profile")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.blFeeding)
                                        Text(String(format: NSLocalizedString("feedLog.lastSide %@", comment: ""), lastSide.displayName))
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.blTextSecondary)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.blTextTertiary)
                                        Text(String(format: NSLocalizedString("feedLog.suggested %@", comment: ""), side.displayName))
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.blFeeding)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.blFeeding.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }

                            // Timer mode toggle (only for new records, not editing ongoing)
                            if !isEditing {
                                Toggle(isOn: $isTimerMode) {
                                    Label(NSLocalizedString("feedLog.useTimer", comment: ""), systemImage: "timer")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.blTextPrimary)
                                }
                                .tint(.blFeeding)
                                .padding(16)
                                .background(Color.blSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            // Banner when editing an ongoing feeding timer
                            if isEditingOngoingFeeding {
                                HStack(spacing: 10) {
                                    Image(systemName: "timer")
                                        .font(.system(size: 16))
                                        .foregroundColor(.blFeeding)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(NSLocalizedString("feedLog.ongoing", comment: ""))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.blTextPrimary)
                                        Text(NSLocalizedString("feedLog.ongoingHint", comment: ""))
                                            .font(.system(size: 13))
                                            .foregroundColor(.blTextSecondary)
                                    }
                                }
                                .padding(14)
                                .background(Color.blFeeding.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.blFeeding.opacity(0.3), lineWidth: 1)
                                )
                            }

                            // Warning: another feeding timer already running
                            if isTimerMode && hasExistingOngoingFeeding && !isEditing {
                                HStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.blGrowth)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(NSLocalizedString("feedLog.timerRunning", comment: ""))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.blTextPrimary)
                                        Text(NSLocalizedString("feedLog.timerRunningHint", comment: ""))
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

                            // Duration (manual mode only)
                            if !isTimerMode {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Label(NSLocalizedString("feedLog.duration", comment: ""), systemImage: "timer")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.blTextSecondary)
                                        Spacer()
                                        Text(durationDisplayText)
                                            .font(.system(size: 17, weight: .bold))
                                            .foregroundColor(.blFeeding)
                                    }
                                    Slider(value: $duration, in: 1...180, step: 1)
                                        .tint(.blFeeding)
                                        .accessibilityLabel(NSLocalizedString("feedLog.duration", comment: ""))
                                        .accessibilityValue(durationAccessibilityText)
                                }
                            }
                        }

                        // Amount (formula/pump/solid)
                        if feedType == .formula || feedType == .pump || feedType == .solid {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label(feedType == .pump
                                          ? NSLocalizedString("feedLog.amountPumped", comment: "")
                                          : NSLocalizedString("feedLog.amount", comment: ""),
                                          systemImage: feedType == .pump ? "drop.halffull" : "scalemass.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.blTextSecondary)
                                    Spacer()
                                    Text(unit == .metric
                                         ? "\(Int(amount)) \(unit.volumeLabel)"
                                         : String(format: "%.1f %@", amount, unit.volumeLabel))
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(.blFeeding)
                                }
                                Slider(value: $amount, in: 0...maxAmount, step: amountStep)
                                    .tint(.blFeeding)
                                    .accessibilityLabel(NSLocalizedString("feedLog.amount", comment: ""))
                                    .accessibilityValue(Self.accessibilityVolumeText(amount: amount, unit: unit))
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
                                    // Show date + time when recording to a past day,
                                    // otherwise just the time for today.
                                    if isTimestampPastDay {
                                        Text(timestamp.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.blFeeding)
                                    } else {
                                        Text(timestamp.formatted(date: .omitted, time: .shortened))
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.blFeeding)
                                    }
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
                                DatePicker("Feeding time", selection: $timestamp, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .tint(.blFeeding)
                                    .labelsHidden()
                                    .accessibilityLabel(NSLocalizedString("a11y.feedingTime", comment: ""))
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }

                        // Notes with quick-suggestion chips
                        VStack(alignment: .leading, spacing: 10) {
                            Label(NSLocalizedString("log.notesOptional", comment: ""), systemImage: "note.text")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)

                            // Quick-note suggestion chips — contextual to feed type
                            feedingNoteChips

                            TextField(NSLocalizedString("log.addNote", comment: ""), text: $notes, axis: .vertical)
                                .lineLimit(3...5)
                                .padding(14)
                                .background(Color.blSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Button(buttonLabel) {
                            guard !isSaving else { return }
                            isSaving = true
                            let hasDuration = feedType == .breast || feedType == .pump
                            let hasAmount = feedType == .formula || feedType == .pump || feedType == .solid
                            // Zero out irrelevant fields to avoid stale data across type switches
                            let amountML = hasAmount ? unit.volumeToML(amount) : 0
                            var ok = false
                            if let record = editingRecord {
                                // When ending an ongoing feeding, recalculate duration
                                // at save time to avoid stale elapsed-time values.
                                let finalDuration: Int
                                if isEditingOngoingFeeding && hasDuration {
                                    let elapsed = Date().timeIntervalSince(timestamp) / 60.0
                                    finalDuration = Int(max(1, min(180, elapsed.rounded())))
                                } else {
                                    finalDuration = hasDuration ? Int(duration) : 0
                                }
                                ok = vm.updateFeeding(
                                    record,
                                    type: feedType,
                                    side: hasDuration ? side : nil,
                                    durationMinutes: finalDuration,
                                    amountML: amountML,
                                    notes: notes,
                                    timestamp: timestamp
                                )
                                appState.showToast(ok ? NSLocalizedString("feedLog.updated", comment: "") : NSLocalizedString("feedLog.saveFailed", comment: ""),
                                                   icon: ok ? "pencil.circle.fill" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blFeeding : .red)
                            } else if isTimerMode && supportsTimer {
                                // Start a feeding timer (ongoing record)
                                ok = vm.startFeeding(
                                    type: feedType,
                                    side: side,
                                    notes: notes,
                                    timestamp: timestamp
                                )
                                appState.showToast(ok ? NSLocalizedString("feedLog.timerStarted", comment: "") : NSLocalizedString("feedLog.saveFailed", comment: ""),
                                                   icon: ok ? "timer" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blFeeding : .red)
                            } else {
                                ok = vm.logFeeding(
                                    type: feedType,
                                    side: hasDuration ? side : nil,
                                    durationMinutes: hasDuration ? Int(duration) : 0,
                                    amountML: amountML,
                                    notes: notes,
                                    timestamp: timestamp
                                )
                                appState.showToast(ok ? NSLocalizedString("feedLog.logged", comment: "") : NSLocalizedString("feedLog.saveFailed", comment: ""),
                                                   icon: ok ? "drop.fill" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blFeeding : .red)
                            }
                            if ok {
                                Self.saveLastFeedType(feedType)
                                Haptic.success()
                                dismiss()
                            } else { Haptic.error(); isSaving = false }
                        }
                        .buttonStyle(BLPrimaryButton(color: .blFeeding))
                        .disabled(!canSave || isSaving)
                        .opacity(canSave && !isSaving ? 1 : 0.5)
                        .padding(.top, 8)

                        if isTimerMode && supportsTimer && !isEditing && hasExistingOngoingFeeding {
                            Text(NSLocalizedString("feedLog.timerActive", comment: ""))
                                .font(.system(size: 13))
                                .foregroundColor(.blGrowth)
                                .frame(maxWidth: .infinity)
                        } else if isTimerMode && supportsTimer && !isEditing {
                            Text(NSLocalizedString("feedLog.timerHint", comment: ""))
                                .font(.system(size: 13))
                                .foregroundColor(.blTextSecondary)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                        } else if !canSave {
                            Text(NSLocalizedString("feedLog.setAmount", comment: ""))
                                .font(.system(size: 13))
                                .foregroundColor(.blTextSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(24)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? NSLocalizedString("feedLog.editTitle", comment: "") : NSLocalizedString("feedLog.title", comment: ""))
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
                    .foregroundColor(.blFeeding)
                }
            }
            .onChange(of: feedType) { _, newType in
                let usesDuration = newType == .breast || newType == .pump
                let usesAmount = newType == .formula || newType == .pump || newType == .solid
                // Reset fields that are irrelevant to the new type
                if !usesDuration { duration = 10 }
                if !usesAmount { amount = 0 }
                // Disable timer mode for types that don't support it
                if !supportsTimer { isTimerMode = false }
            }
            .onAppear {
                populateFromRecord()
                // Apply initial date for retroactive logging (only when creating new records)
                if !isEditing, let initialDate {
                    timestamp = initialDate
                }
                if !isEditing {
                    restoreLastFeedType()
                    suggestNextSide()
                }
                checkExistingOngoingFeeding()
                startElapsedTimerIfNeeded()
            }
            .onDisappear {
                elapsedTimer?.invalidate()
                elapsedTimer = nil
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
        }
    }

    // MARK: - Quick Note Suggestions

    /// Common feeding observations, contextual to the selected feed type.
    private var feedingNoteSuggestions: [String] {
        switch feedType {
        case .breast:
            return [
                NSLocalizedString("feedLog.chip.goodLatch", comment: ""),
                NSLocalizedString("feedLog.chip.fussy", comment: ""),
                NSLocalizedString("feedLog.chip.fellAsleep", comment: ""),
                NSLocalizedString("feedLog.chip.spitUp", comment: ""),
            ]
        case .formula:
            return [
                NSLocalizedString("feedLog.chip.finishedAll", comment: ""),
                NSLocalizedString("feedLog.chip.refused", comment: ""),
                NSLocalizedString("feedLog.chip.spitUp", comment: ""),
                NSLocalizedString("feedLog.chip.gassy", comment: ""),
            ]
        case .solid:
            return [
                NSLocalizedString("feedLog.chip.lovedIt", comment: ""),
                NSLocalizedString("feedLog.chip.refused", comment: ""),
                NSLocalizedString("feedLog.chip.newFood", comment: ""),
                NSLocalizedString("feedLog.chip.messy", comment: ""),
            ]
        case .pump:
            return [
                NSLocalizedString("feedLog.chip.goodOutput", comment: ""),
                NSLocalizedString("feedLog.chip.lowOutput", comment: ""),
                NSLocalizedString("feedLog.chip.painful", comment: ""),
            ]
        }
    }

    private func chipAlreadyAdded(_ chip: String) -> Bool {
        notes.localizedCaseInsensitiveContains(chip)
    }

    private var feedingNoteChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(feedingNoteSuggestions, id: \.self) { chip in
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
                        .foregroundColor(isAdded ? .white : .blFeeding)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isAdded ? Color.blFeeding : Color.blFeeding.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(chip)
                .accessibilityAddTraits(isAdded ? .isSelected : [])
            }
        }
    }

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
        feedType = FeedType(rawValue: r.feedType ?? "") ?? .breast
        side = BreastSide(rawValue: r.breastSide ?? "") ?? .left
        amount = unit.volumeFromML(r.amountML)
        notes = r.notes ?? ""
        timestamp = r.timestamp ?? Date()

        let isOngoing = r.durationMinutes == 0
            && (feedType == .breast || feedType == .pump)
        if isOngoing {
            // Calculate elapsed minutes from start time as a sensible default
            let elapsed = Date().timeIntervalSince(timestamp) / 60.0
            duration = max(1, min(180, elapsed.rounded()))
            isEditingOngoingFeeding = true
        } else {
            duration = max(1, Double(r.durationMinutes))
        }
    }

    /// Check if another feeding timer (breast/pump with durationMinutes == 0) is already running.
    private func checkExistingOngoingFeeding() {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<CDFeedingRecord> = CDFeedingRecord.fetchRequest()
        req.predicate = NSPredicate(format: "durationMinutes == 0 AND (feedType == %@ OR feedType == %@)",
                                    FeedType.breast.rawValue, FeedType.pump.rawValue)
        // When editing, we need to fetch at least 2 results so that if the first
        // result is the record being edited, we can still detect a second ongoing
        // feeding. With fetchLimit=1 the duplicate could be masked.
        req.fetchLimit = isEditing ? 2 : 1
        guard let results = try? ctx.fetch(req) else { return }
        if let editing = editingRecord {
            hasExistingOngoingFeeding = results.contains(where: { $0.objectID != editing.objectID })
        } else {
            hasExistingOngoingFeeding = !results.isEmpty
        }
    }

    /// Fetch the last breast/pump feeding's side and auto-select the opposite
    private func suggestNextSide() {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<CDFeedingRecord> = CDFeedingRecord.fetchRequest()
        req.predicate = NSPredicate(format: "(feedType == %@ OR feedType == %@) AND breastSide != nil AND breastSide != %@",
                                    FeedType.breast.rawValue, FeedType.pump.rawValue, "")
        req.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        req.fetchLimit = 1

        guard let last = (try? ctx.fetch(req))?.first,
              let lastRaw = last.breastSide,
              let lastSide = BreastSide(rawValue: lastRaw) else { return }

        lastSideUsed = lastSide

        // Auto-select opposite side
        let suggested: BreastSide
        switch lastSide {
        case .left:  suggested = .right
        case .right: suggested = .left
        case .both:  suggested = .both
        }
        side = suggested
        didAutoSuggestSide = true
    }

    // MARK: - Remember Last Feed Type

    /// Restore the last-used feed type so the user doesn't have to re-select every time.
    /// Only applied for new records — editing always uses the record's own feed type.
    private func restoreLastFeedType() {
        guard let raw = UserDefaults.standard.string(forKey: Self.lastFeedTypeKey),
              let saved = FeedType(rawValue: raw) else { return }
        feedType = saved
    }

    /// Persist the selected feed type for next time.
    private static func saveLastFeedType(_ type: FeedType) {
        UserDefaults.standard.set(type.rawValue, forKey: lastFeedTypeKey)
    }

    /// Start a 15-second timer that keeps the displayed duration in sync
    /// with the actual elapsed time while editing an ongoing feeding.
    private func startElapsedTimerIfNeeded() {
        guard isEditingOngoingFeeding else { return }
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { @MainActor in
                let elapsed = Date().timeIntervalSince(timestamp) / 60.0
                duration = max(1, min(180, elapsed.rounded()))
            }
        }
    }
}
