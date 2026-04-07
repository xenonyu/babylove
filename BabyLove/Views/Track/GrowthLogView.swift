import SwiftUI

struct GrowthLogView: View {
    @ObservedObject var vm: TrackViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    /// When non-nil, we are editing an existing record
    var editingRecord: CDGrowthRecord?
    /// Optional initial date for the record (used for retroactive logging from past dates)
    var initialDate: Date? = nil

    @State private var weightKG = ""
    @State private var heightCM = ""
    @State private var headCM   = ""
    @State private var notes    = ""
    @State private var recordDate = Date()
    @State private var showDatePicker = false
    @State private var previousRecord: CDGrowthRecord?
    @State private var showJumpConfirmation = false
    /// Guards against double-tap creating duplicate records
    @State private var isSaving = false

    private var isEditing: Bool { editingRecord != nil }
    private var unit: MeasurementUnit { appState.measurementUnit }
    /// Whether the record date falls on a different calendar day than today
    private var isRecordDatePastDay: Bool {
        !Calendar.current.isDateInToday(recordDate)
    }

    /// At least one measurement must be a valid positive number
    private var hasValidMeasurement: Bool {
        [weightKG, heightCM, headCM].contains { Double($0).map { $0 > 0 } ?? false }
    }

    // MARK: - Realistic bounds (in display units)
    /// Returns a validation warning if any entered value is unrealistically large/negative
    private var validationWarning: String? {
        if let w = Double(weightKG) {
            if w < 0 { return NSLocalizedString("growthLog.weightNeg", comment: "") }
            let maxWeight = unit == .metric ? 30.0 : 66.0  // 30 kg / 66 lbs
            let maxLabel = unit == .metric
                ? NSLocalizedString("growthLog.maxWeight.metric", comment: "")
                : NSLocalizedString("growthLog.maxWeight.imperial", comment: "")
            if w > maxWeight { return String(format: NSLocalizedString("growthLog.weightHigh %@", comment: ""), maxLabel) }
        }
        if let h = Double(heightCM) {
            if h < 0 { return NSLocalizedString("growthLog.heightNeg", comment: "") }
            let maxHeight = unit == .metric ? 130.0 : 51.0  // 130 cm / 51 in
            let maxLabel = unit == .metric
                ? NSLocalizedString("growthLog.maxHeight.metric", comment: "")
                : NSLocalizedString("growthLog.maxHeight.imperial", comment: "")
            if h > maxHeight { return String(format: NSLocalizedString("growthLog.heightHigh %@", comment: ""), maxLabel) }
        }
        if let hc = Double(headCM) {
            if hc < 0 { return NSLocalizedString("growthLog.headNeg", comment: "") }
            let maxHead = unit == .metric ? 60.0 : 24.0  // 60 cm / 24 in
            let maxLabel = unit == .metric
                ? NSLocalizedString("growthLog.maxHead.metric", comment: "")
                : NSLocalizedString("growthLog.maxHead.imperial", comment: "")
            if hc > maxHead { return String(format: NSLocalizedString("growthLog.headHigh %@", comment: ""), maxLabel) }
        }
        return nil
    }

    /// Soft warning when a new value deviates significantly from the previous record.
    /// Does NOT block saving — just alerts the user to double-check for typos.
    private var jumpWarnings: [String] {
        guard let prev = previousRecord else { return [] }
        var warnings: [String] = []

        func checkJump(newText: String, prevMetric: Double, label: String, convertFromKG: Bool) {
            guard prevMetric > 0, let newVal = Double(newText), newVal > 0 else { return }
            let prevDisplay = convertFromKG ? unit.weightFromKG(prevMetric) : unit.lengthFromCM(prevMetric)
            guard prevDisplay > 0 else { return }
            let ratio = newVal / prevDisplay
            // Flag if value changed by more than 3× or dropped by more than 60%
            if ratio > 3.0 || ratio < 0.4 {
                let unitLabel = convertFromKG ? unit.weightLabel : unit.heightLabel
                let prevStr = convertFromKG ? String(format: "%.2f", prevDisplay) : String(format: "%.1f", prevDisplay)
                warnings.append(String(format: NSLocalizedString("growthLog.jumpWarning %@ %@ %@ %@", comment: ""), label, prevStr, newText, unitLabel))
            }
        }

        checkJump(newText: weightKG, prevMetric: prev.weightKG, label: NSLocalizedString("growthLog.weight", comment: ""), convertFromKG: true)
        checkJump(newText: heightCM, prevMetric: prev.heightCM, label: NSLocalizedString("growthLog.height", comment: ""), convertFromKG: false)
        checkJump(newText: headCM, prevMetric: prev.headCircumferenceCM, label: NSLocalizedString("growthLog.headCirc", comment: ""), convertFromKG: false)
        return warnings
    }

    private var canSave: Bool {
        hasValidMeasurement && validationWarning == nil
    }

    // MARK: - Previous Measurement Reference

    /// Formatted string showing the previous weight for quick reference, e.g. "Last: 5.43 kg · Apr 1"
    private var previousWeightText: String? {
        guard let prev = previousRecord, prev.weightKG > 0 else { return nil }
        let w = unit.weightFromKG(prev.weightKG)
        let valStr = String(format: "%.2f %@", w, unit.weightLabel)
        return formatPreviousText(valStr, date: prev.date)
    }

    /// Formatted string showing the previous height for quick reference
    private var previousHeightText: String? {
        guard let prev = previousRecord, prev.heightCM > 0 else { return nil }
        let h = unit.lengthFromCM(prev.heightCM)
        let valStr = String(format: "%.1f %@", h, unit.heightLabel)
        return formatPreviousText(valStr, date: prev.date)
    }

    /// Formatted string showing the previous head circumference for quick reference
    private var previousHeadText: String? {
        guard let prev = previousRecord, prev.headCircumferenceCM > 0 else { return nil }
        let hc = unit.lengthFromCM(prev.headCircumferenceCM)
        let valStr = String(format: "%.1f %@", hc, unit.heightLabel)
        return formatPreviousText(valStr, date: prev.date)
    }

    /// Combine a value string with an optional date into "Last: {value} · {date}"
    private func formatPreviousText(_ valueStr: String, date: Date?) -> String {
        if let date {
            let dateStr = BLDateFormatters.monthDay.string(from: date)
            return String(format: NSLocalizedString("growthLog.previousWithDate %@ %@", comment: ""), valueStr, dateStr)
        }
        return String(format: NSLocalizedString("growthLog.previous %@", comment: ""), valueStr)
    }

    /// Whether the form has meaningful user input that would be lost on dismiss.
    private var hasUnsavedChanges: Bool {
        if isEditing { return true }
        if !weightKG.isEmpty || !heightCM.isEmpty || !headCM.isEmpty { return true }
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Retroactive date banner — shown when logging to a past day
                        if isRecordDatePastDay && !isEditing {
                            HStack(spacing: 10) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 16))
                                    .foregroundColor(.blGrowth)
                                Text(String(format: NSLocalizedString("log.recordingFor %@", comment: ""), recordDate.formatted(date: .long, time: .omitted)))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.blTextPrimary)
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.blGrowth.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.blGrowth.opacity(0.2), lineWidth: 1)
                            )
                        }

                        measurementField(
                            label: NSLocalizedString("growthLog.weight", comment: ""),
                            unit: unit.weightLabel,
                            icon: "scalemass.fill",
                            color: .blGrowth,
                            value: $weightKG,
                            placeholder: unit == .metric
                                ? NSLocalizedString("growthLog.weightPlaceholder.metric", comment: "")
                                : NSLocalizedString("growthLog.weightPlaceholder.imperial", comment: ""),
                            previousText: previousWeightText
                        )
                        measurementField(
                            label: NSLocalizedString("growthLog.height", comment: ""),
                            unit: unit.heightLabel,
                            icon: "ruler.fill",
                            color: .blGrowth,
                            value: $heightCM,
                            placeholder: unit == .metric
                                ? NSLocalizedString("growthLog.heightPlaceholder.metric", comment: "")
                                : NSLocalizedString("growthLog.heightPlaceholder.imperial", comment: ""),
                            previousText: previousHeightText
                        )
                        measurementField(
                            label: NSLocalizedString("growthLog.headCirc", comment: ""),
                            unit: unit.heightLabel,
                            icon: "circle.dotted",
                            color: .blGrowth,
                            value: $headCM,
                            placeholder: unit == .metric
                                ? NSLocalizedString("growthLog.headPlaceholder.metric", comment: "")
                                : NSLocalizedString("growthLog.headPlaceholder.imperial", comment: ""),
                            previousText: previousHeadText
                        )

                        // Date
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                withAnimation(.spring(response: 0.3)) { showDatePicker.toggle() }
                            } label: {
                                HStack {
                                    Label(NSLocalizedString("growthLog.date", comment: ""), systemImage: "calendar")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.blTextSecondary)
                                    Spacer()
                                    Text(recordDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.blGrowth)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.blTextTertiary)
                                        .rotationEffect(.degrees(showDatePicker ? 90 : 0))
                                }
                                .padding(14)
                                .background(Color.blSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            if showDatePicker {
                                DatePicker("Measurement date", selection: $recordDate, in: ...Date(), displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .tint(.blGrowth)
                                    .labelsHidden()
                                    .accessibilityLabel(NSLocalizedString("a11y.measurementDate", comment: ""))
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Label(NSLocalizedString("log.notes", comment: ""), systemImage: "note.text")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                            TextField(NSLocalizedString("growthLog.notesPlaceholder", comment: ""), text: $notes, axis: .vertical)
                                .lineLimit(2...4)
                                .padding(14)
                                .background(Color.blSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Button(isEditing
                               ? NSLocalizedString("growthLog.updateMeasurements", comment: "")
                               : NSLocalizedString("growthLog.saveMeasurements", comment: "")) {
                            guard !isSaving else { return }
                            // If there are jump warnings, ask the user to confirm before saving
                            if !jumpWarnings.isEmpty {
                                showJumpConfirmation = true
                            } else {
                                performSave()
                            }
                        }
                        .buttonStyle(BLPrimaryButton(color: .blGrowth))
                        .disabled(!canSave || isSaving)
                        .opacity(canSave && !isSaving ? 1 : 0.5)
                        .padding(.top, 8)

                        if let warning = validationWarning {
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.blPrimary)
                                .frame(maxWidth: .infinity)
                        } else if !hasValidMeasurement {
                            Text(NSLocalizedString("growthLog.enterOne", comment: ""))
                                .font(.system(size: 13))
                                .foregroundColor(.blTextSecondary)
                                .frame(maxWidth: .infinity)
                        }

                        // Soft warnings for large jumps from previous record (don't block save)
                        if !jumpWarnings.isEmpty {
                            VStack(spacing: 6) {
                                ForEach(jumpWarnings, id: \.self) { warning in
                                    Label(warning, systemImage: "exclamationmark.circle.fill")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.orange)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(12)
                            .background(Color.orange.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                    .padding(24)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? NSLocalizedString("growthLog.editTitle", comment: "") : NSLocalizedString("growthLog.title", comment: ""))
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
                    .foregroundColor(.blGrowth)
                }
            }
            .alert(NSLocalizedString("growthLog.jumpConfirmTitle", comment: "Unusual value confirmation"), isPresented: $showJumpConfirmation) {
                Button(NSLocalizedString("growthLog.jumpConfirmSave", comment: "Save anyway"), role: .destructive) {
                    performSave()
                }
                Button(NSLocalizedString("growthLog.jumpConfirmCancel", comment: "Go back and fix"), role: .cancel) { }
            } message: {
                Text(jumpWarnings.joined(separator: "\n"))
            }
            .onAppear {
                populateFromRecord()
                // Apply initial date for retroactive logging (only when creating new records)
                if !isEditing, let initialDate {
                    recordDate = initialDate
                }
                // Fetch the latest previous record to enable jump-detection warnings
                previousRecord = vm.latestGrowthRecord(excluding: editingRecord?.id)
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
        }
    }

    /// Performs the actual save/update after any confirmations are resolved.
    private func performSave() {
        guard !isSaving else { return }
        isSaving = true
        let wKG: Double? = Self.parseMetric(weightKG, convert: unit.weightToKG, isEditing: isEditing)
        let hCM: Double? = Self.parseMetric(heightCM, convert: unit.lengthToCM, isEditing: isEditing)
        let hd: Double? = Self.parseMetric(headCM, convert: unit.lengthToCM, isEditing: isEditing)
        var ok = false
        if let record = editingRecord {
            ok = vm.updateGrowth(record, weightKG: wKG, heightCM: hCM, headCM: hd, date: recordDate, notes: notes)
            appState.showToast(ok ? NSLocalizedString("growthLog.updated", comment: "") : NSLocalizedString("growthLog.saveFailed", comment: ""),
                               icon: ok ? "pencil.circle.fill" : "exclamationmark.triangle.fill",
                               color: ok ? .blGrowth : .red)
        } else {
            ok = vm.logGrowth(weightKG: wKG, heightCM: hCM, headCM: hd, date: recordDate, notes: notes)
            appState.showToast(ok ? NSLocalizedString("growthLog.logged", comment: "") : NSLocalizedString("growthLog.saveFailed", comment: ""),
                               icon: ok ? "chart.bar.fill" : "exclamationmark.triangle.fill",
                               color: ok ? .blGrowth : .red)
        }
        if ok { Haptic.success(); dismiss() } else { Haptic.error(); isSaving = false }
    }

    private func populateFromRecord() {
        guard let r = editingRecord else { return }
        let w = unit.weightFromKG(r.weightKG)
        let h = unit.lengthFromCM(r.heightCM)
        let hc = unit.lengthFromCM(r.headCircumferenceCM)
        weightKG = w > 0 ? String(format: "%.2f", w) : ""
        heightCM = h > 0 ? String(format: "%.1f", h) : ""
        headCM = hc > 0 ? String(format: "%.1f", hc) : ""
        notes = r.notes ?? ""
        recordDate = r.date ?? Date()
    }

    /// Strips non-numeric characters, keeping at most one decimal separator
    /// and capping fractional digits at 2 (e.g. "5.55" ok, "5.555" → "5.55").
    private static func sanitizeDecimalInput(_ input: String) -> String {
        if input.isEmpty { return input }
        var result = ""
        var hasDecimal = false
        var fractionDigits = 0
        for ch in input {
            if ch.isNumber {
                if hasDecimal {
                    guard fractionDigits < 2 else { continue }
                    fractionDigits += 1
                }
                result.append(ch)
            } else if (ch == "." || ch == ",") && !hasDecimal {
                hasDecimal = true
                result.append(".")   // normalise comma → dot
            }
            // silently drop any other character (minus, letters, extra dots…)
        }
        return result
    }

    private func measurementField(
        label: String,
        unit: String,
        icon: String,
        color: Color,
        value: Binding<String>,
        placeholder: String,
        previousText: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.blTextSecondary)
                Spacer()
                if let previousText {
                    Text(previousText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blTextTertiary)
                }
            }
            HStack {
                TextField(placeholder, text: value)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 17))
                    .onChange(of: value.wrappedValue) { oldValue, newValue in
                        let sanitized = Self.sanitizeDecimalInput(newValue)
                        if sanitized != newValue {
                            value.wrappedValue = sanitized
                        }
                    }
                Spacer()
                Text(unit)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(color)
            }
            .padding(14)
            .background(Color.blSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    /// Parse a measurement text field to metric value for storage.
    /// - When the text parses to a number, convert via the given unit function.
    /// - When the text is empty and we're editing, return explicit 0 to clear the value.
    /// - When the text is empty and we're adding, return nil (leave at CoreData default).
    private static func parseMetric(_ text: String, convert: (Double) -> Double, isEditing: Bool) -> Double? {
        if let val = Double(text) { return convert(val) }
        return isEditing ? 0 : nil
    }
}
