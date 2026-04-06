import SwiftUI

struct DiaperLogView: View {
    @ObservedObject var vm: TrackViewModel
    @EnvironmentObject var appState: AppState
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
                ScrollView {
                    VStack(spacing: 24) {
                        // Type selection
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Diaper Type")
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
                                    .accessibilityLabel("\(t.displayName) diaper")
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
                                DatePicker("Diaper change time", selection: $timestamp, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .tint(.blDiaper)
                                    .labelsHidden()
                                    .accessibilityLabel("Diaper change time")
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }

                        // Notes
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Notes (optional)", systemImage: "note.text")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                            TextField("Color, consistency, or other notes…", text: $notes, axis: .vertical)
                                .lineLimit(2...4)
                                .padding(14)
                                .background(Color.blSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Button(isEditing ? "Update Diaper" : "Log Diaper Change") {
                            var ok = false
                            if let record = editingRecord {
                                ok = vm.updateDiaper(record, type: diaperType, notes: notes, timestamp: timestamp)
                                appState.showToast(ok ? "Diaper updated" : "Save failed — try again",
                                                   icon: ok ? "pencil.circle.fill" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blDiaper : .red)
                            } else {
                                ok = vm.logDiaper(type: diaperType, notes: notes, timestamp: timestamp)
                                appState.showToast(ok ? "Diaper logged" : "Save failed — try again",
                                                   icon: ok ? "oval.fill" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blDiaper : .red)
                            }
                            if ok { Haptic.success(); dismiss() } else { Haptic.error() }
                        }
                        .buttonStyle(BLPrimaryButton(color: .blDiaper))
                        .padding(.top, 8)
                    }
                    .padding(24)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Edit Diaper" : "Log Diaper")
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
                    .foregroundColor(.blDiaper)
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
