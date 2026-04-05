import SwiftUI

struct GrowthLogView: View {
    @ObservedObject var vm: TrackViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    /// When non-nil, we are editing an existing record
    var editingRecord: CDGrowthRecord?

    @State private var weightKG = ""
    @State private var heightCM = ""
    @State private var headCM   = ""
    @State private var notes    = ""
    @State private var recordDate = Date()
    @State private var showDatePicker = false

    private var isEditing: Bool { editingRecord != nil }
    private var unit: MeasurementUnit { appState.measurementUnit }

    /// At least one measurement must be a valid positive number
    private var hasValidMeasurement: Bool {
        [weightKG, heightCM, headCM].contains { Double($0).map { $0 > 0 } ?? false }
    }

    // MARK: - Realistic bounds (in display units)
    /// Returns a validation warning if any entered value is unrealistically large/negative
    private var validationWarning: String? {
        if let w = Double(weightKG) {
            if w < 0 { return "Weight cannot be negative" }
            let maxWeight = unit == .metric ? 30.0 : 66.0  // 30 kg / 66 lbs
            if w > maxWeight { return "Weight seems too high (\(unit == .metric ? "max ~30 kg" : "max ~66 lbs"))" }
        }
        if let h = Double(heightCM) {
            if h < 0 { return "Height cannot be negative" }
            let maxHeight = unit == .metric ? 130.0 : 51.0  // 130 cm / 51 in
            if h > maxHeight { return "Height seems too high (\(unit == .metric ? "max ~130 cm" : "max ~51 in"))" }
        }
        if let hc = Double(headCM) {
            if hc < 0 { return "Head circumference cannot be negative" }
            let maxHead = unit == .metric ? 60.0 : 24.0  // 60 cm / 24 in
            if hc > maxHead { return "Head circumference seems too high (\(unit == .metric ? "max ~60 cm" : "max ~24 in"))" }
        }
        return nil
    }

    private var canSave: Bool {
        hasValidMeasurement && validationWarning == nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        measurementField(
                            label: "Weight",
                            unit: unit.weightLabel,
                            icon: "scalemass.fill",
                            color: .blGrowth,
                            value: $weightKG,
                            placeholder: unit == .metric ? "e.g. 5.5" : "e.g. 12.1"
                        )
                        measurementField(
                            label: "Height / Length",
                            unit: unit.heightLabel,
                            icon: "ruler.fill",
                            color: .blGrowth,
                            value: $heightCM,
                            placeholder: unit == .metric ? "e.g. 60.5" : "e.g. 23.8"
                        )
                        measurementField(
                            label: "Head Circumference",
                            unit: unit.heightLabel,
                            icon: "circle.dotted",
                            color: .blGrowth,
                            value: $headCM,
                            placeholder: unit == .metric ? "e.g. 40.2" : "e.g. 15.8"
                        )

                        // Date
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                withAnimation(.spring(response: 0.3)) { showDatePicker.toggle() }
                            } label: {
                                HStack {
                                    Label("Date", systemImage: "calendar")
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
                                    .accessibilityLabel("Measurement date")
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Label("Notes", systemImage: "note.text")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                            TextField("Doctor's notes, observations…", text: $notes, axis: .vertical)
                                .lineLimit(2...4)
                                .padding(14)
                                .background(Color.blSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Button(isEditing ? "Update Measurements" : "Save Measurements") {
                            // Convert from display unit to metric for storage.
                            // When editing, an empty field means the user intentionally
                            // cleared that measurement → pass 0.0 so updateGrowth
                            // overwrites the old value. When adding, nil means "not measured".
                            let wKG: Double? = {
                                if let v = Double(weightKG) { return unit.weightToKG(v) }
                                return isEditing ? 0.0 : nil
                            }()
                            let hCM: Double? = {
                                if let v = Double(heightCM) { return unit.lengthToCM(v) }
                                return isEditing ? 0.0 : nil
                            }()
                            let hd: Double? = {
                                if let v = Double(headCM) { return unit.lengthToCM(v) }
                                return isEditing ? 0.0 : nil
                            }()
                            var ok = false
                            if let record = editingRecord {
                                ok = vm.updateGrowth(record, weightKG: wKG, heightCM: hCM, headCM: hd, date: recordDate, notes: notes)
                                appState.showToast(ok ? "Growth updated" : "Save failed — try again",
                                                   icon: ok ? "pencil.circle.fill" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blGrowth : .red)
                            } else {
                                ok = vm.logGrowth(weightKG: wKG, heightCM: hCM, headCM: hd, date: recordDate, notes: notes)
                                appState.showToast(ok ? "Growth logged" : "Save failed — try again",
                                                   icon: ok ? "chart.bar.fill" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blGrowth : .red)
                            }
                            if ok { Haptic.success(); dismiss() } else { Haptic.error() }
                        }
                        .buttonStyle(BLPrimaryButton(color: .blGrowth))
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)
                        .padding(.top, 8)

                        if let warning = validationWarning {
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.blPrimary)
                                .frame(maxWidth: .infinity)
                        } else if !hasValidMeasurement {
                            Text("Enter at least one measurement to save")
                                .font(.system(size: 13))
                                .foregroundColor(.blTextSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(24)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Edit Growth" : "Log Growth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blGrowth)
                }
            }
            .onAppear { populateFromRecord() }
        }
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

    private func measurementField(
        label: String,
        unit: String,
        icon: String,
        color: Color,
        value: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(label, systemImage: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.blTextSecondary)
            HStack {
                TextField(placeholder, text: value)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 17))
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
}
