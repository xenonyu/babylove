import SwiftUI

struct GrowthLogView: View {
    @ObservedObject var vm: TrackViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var weightKG = ""
    @State private var heightCM = ""
    @State private var headCM   = ""
    @State private var notes    = ""

    private var unit: MeasurementUnit { appState.measurementUnit }

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

                        Button("Save Measurements") {
                            let wKG = Double(weightKG)
                            let hCM = Double(heightCM)
                            let hd  = Double(headCM)
                            vm.logGrowth(
                                weightKG: wKG,
                                heightCM: hCM,
                                headCM: hd,
                                notes: notes
                            )
                            dismiss()
                        }
                        .buttonStyle(BLPrimaryButton(color: .blGrowth))
                        .padding(.top, 8)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Log Growth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
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
