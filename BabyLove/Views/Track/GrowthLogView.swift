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
                                DatePicker("", selection: $recordDate, in: ...Date(), displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .tint(.blGrowth)
                                    .labelsHidden()
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
                            Haptic.success()
                            // Convert from display unit to metric for storage
                            let wKG = Double(weightKG).map { unit.weightToKG($0) }
                            let hCM = Double(heightCM).map { unit.lengthToCM($0) }
                            let hd  = Double(headCM).map { unit.lengthToCM($0) }
                            if let record = editingRecord {
                                vm.updateGrowth(record, weightKG: wKG, heightCM: hCM, headCM: hd, date: recordDate, notes: notes)
                                appState.showToast("Growth updated", icon: "pencil.circle.fill", color: .blGrowth)
                            } else {
                                vm.logGrowth(weightKG: wKG, heightCM: hCM, headCM: hd, date: recordDate, notes: notes)
                                appState.showToast("Growth logged", icon: "chart.bar.fill", color: .blGrowth)
                            }
                            dismiss()
                        }
                        .buttonStyle(BLPrimaryButton(color: .blGrowth))
                        .disabled(!hasValidMeasurement)
                        .opacity(hasValidMeasurement ? 1 : 0.5)
                        .padding(.top, 8)

                        if !hasValidMeasurement {
                            Text("Enter at least one measurement to save")
                                .font(.system(size: 13))
                                .foregroundColor(.blTextSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle(isEditing ? "Edit Growth" : "Log Growth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
