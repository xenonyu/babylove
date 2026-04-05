import SwiftUI

struct FeedingLogView: View {
    @ObservedObject var vm: TrackViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var feedType: FeedType = .breast
    @State private var side: BreastSide = .left
    @State private var duration: Double = 10
    @State private var amount: Double = 0
    @State private var notes = ""

    private var unit: MeasurementUnit { appState.measurementUnit }
    /// Max amount in display unit (300 ml ≈ 10 oz)
    private var maxAmount: Double { unit == .metric ? 300 : 10 }
    private var amountStep: Double { unit == .metric ? 5 : 0.5 }

    /// Formula/solid require amount > 0; breast/pump always valid (have duration)
    private var canSave: Bool {
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

                        // Feed type picker
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Type", systemImage: "drop.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                            HStack(spacing: 10) {
                                ForEach(FeedType.allCases, id: \.self) { t in
                                    Button {
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
                                }
                            }
                        }

                        // Breast side (when breast)
                        if feedType == .breast || feedType == .pump {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Side", systemImage: "arrow.left.arrow.right")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.blTextSecondary)
                                HStack(spacing: 10) {
                                    ForEach(BreastSide.allCases, id: \.self) { s in
                                        Button {
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
                                    }
                                }
                            }

                            // Duration
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label("Duration", systemImage: "timer")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.blTextSecondary)
                                    Spacer()
                                    Text("\(Int(duration)) min")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(.blFeeding)
                                }
                                Slider(value: $duration, in: 1...60, step: 1)
                                    .tint(.blFeeding)
                            }
                        }

                        // Amount (formula/pump/solid)
                        if feedType == .formula || feedType == .pump || feedType == .solid {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label(feedType == .pump ? "Amount Pumped" : "Amount",
                                          systemImage: feedType == .pump ? "drop.halffull" : "scalemass.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.blTextSecondary)
                                    Spacer()
                                    Text(unit == .metric
                                         ? "\(Int(amount)) ml"
                                         : String(format: "%.1f oz", amount))
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(.blFeeding)
                                }
                                Slider(value: $amount, in: 0...maxAmount, step: amountStep)
                                    .tint(.blFeeding)
                            }
                        }

                        // Notes
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Notes (optional)", systemImage: "note.text")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                            TextField("Add a note…", text: $notes, axis: .vertical)
                                .lineLimit(3...5)
                                .padding(14)
                                .background(Color.blSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Button("Log Feeding") {
                            let amountML = unit.volumeToML(amount)
                            vm.logFeeding(
                                type: feedType,
                                side: (feedType == .breast || feedType == .pump) ? side : nil,
                                durationMinutes: Int(duration),
                                amountML: amountML,
                                notes: notes
                            )
                            dismiss()
                        }
                        .buttonStyle(BLPrimaryButton(color: .blFeeding))
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)
                        .padding(.top, 8)

                        if !canSave {
                            Text("Set the amount before saving")
                                .font(.system(size: 13))
                                .foregroundColor(.blTextSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Log Feeding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
