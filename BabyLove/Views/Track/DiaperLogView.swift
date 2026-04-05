import SwiftUI

struct DiaperLogView: View {
    @ObservedObject var vm: TrackViewModel
    @Environment(\.dismiss) var dismiss

    /// When non-nil, we are editing an existing record
    var editingRecord: CDDiaperRecord?

    @State private var diaperType: DiaperType = .wet
    @State private var notes = ""
    @State private var timestamp = Date()
    @State private var showTimePicker = false

    private var isEditing: Bool { editingRecord != nil }

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

                    // Time
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            withAnimation(.spring(response: 0.3)) { showTimePicker.toggle() }
                        } label: {
                            HStack {
                                Label("Time", systemImage: "clock.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.blTextSecondary)
                                Spacer()
                                Text(timestamp.formatted(date: .omitted, time: .shortened))
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
                            DatePicker("", selection: $timestamp, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                                .tint(.blDiaper)
                                .labelsHidden()
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal, 24)

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

                    Button(isEditing ? "Update Diaper" : "Log Diaper Change") {
                        if let record = editingRecord {
                            vm.updateDiaper(record, type: diaperType, notes: notes, timestamp: timestamp)
                        } else {
                            vm.logDiaper(type: diaperType, notes: notes, timestamp: timestamp)
                        }
                        dismiss()
                    }
                    .buttonStyle(BLPrimaryButton(color: .blDiaper))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
                .padding(.top, 24)
            }
            .navigationTitle(isEditing ? "Edit Diaper" : "Log Diaper")
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
        diaperType = DiaperType(rawValue: r.diaperType ?? "") ?? .wet
        notes = r.notes ?? ""
        timestamp = r.timestamp ?? Date()
    }
}
