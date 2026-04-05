import SwiftUI

struct DiaperLogView: View {
    @ObservedObject var vm: TrackViewModel
    @Environment(\.dismiss) var dismiss

    @State private var diaperType: DiaperType = .wet
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()
                VStack(spacing: 28) {
                    // Type selection
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Diaper Type")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.blTextSecondary)
                            .padding(.horizontal, 24)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                            ForEach(DiaperType.allCases, id: \.self) { t in
                                Button {
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
                            }
                        }
                        .padding(.horizontal, 24)
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Notes (optional)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.blTextSecondary)
                        TextField("Color, consistency, or other notes…", text: $notes, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(14)
                            .background(Color.blSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    Button("Log Diaper Change") {
                        vm.logDiaper(type: diaperType, notes: notes)
                        dismiss()
                    }
                    .buttonStyle(BLPrimaryButton(color: .blDiaper))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
                .padding(.top, 24)
            }
            .navigationTitle("Log Diaper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
