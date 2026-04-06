import SwiftUI

struct DiaperLogView: View {
    @ObservedObject var vm: TrackViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    /// When non-nil, we are editing an existing record
    var editingRecord: CDDiaperRecord?
    /// Optional initial date for the timestamp (used for retroactive logging from past dates)
    var initialDate: Date? = nil

    @State private var diaperType: DiaperType = .wet
    @State private var notes = ""
    @State private var timestamp = Date()
    @State private var showTimePicker = false
    /// Whether the current timestamp falls on a different calendar day than today
    private var isTimestampPastDay: Bool {
        !Calendar.current.isDateInToday(timestamp)
    }

    private var isEditing: Bool { editingRecord != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        // Retroactive date banner — shown when logging to a past day
                        if isTimestampPastDay {
                            HStack(spacing: 10) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 16))
                                    .foregroundColor(.blDiaper)
                                Text(String(format: NSLocalizedString("log.recordingFor %@", comment: ""), timestamp.formatted(date: .long, time: .omitted)))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.blTextPrimary)
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.blDiaper.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.blDiaper.opacity(0.2), lineWidth: 1)
                            )
                        }

                        // Type selection
                        VStack(alignment: .leading, spacing: 14) {
                            Text(NSLocalizedString("diaperLog.diaperType", comment: ""))
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
                                    Label(NSLocalizedString("log.time", comment: ""), systemImage: "clock.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.blTextSecondary)
                                    Spacer()
                                    // Show date + time when recording to a past day
                                    Text(isTimestampPastDay
                                         ? timestamp.formatted(date: .abbreviated, time: .shortened)
                                         : timestamp.formatted(date: .omitted, time: .shortened))
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
                                    .accessibilityLabel(NSLocalizedString("a11y.diaperChangeTime", comment: ""))
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }

                        // Notes
                        VStack(alignment: .leading, spacing: 10) {
                            Label(NSLocalizedString("log.notesOptional", comment: ""), systemImage: "note.text")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                            TextField(NSLocalizedString("diaperLog.notesPlaceholder", comment: ""), text: $notes, axis: .vertical)
                                .lineLimit(2...4)
                                .padding(14)
                                .background(Color.blSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Button(isEditing
                               ? NSLocalizedString("diaperLog.updateDiaper", comment: "")
                               : NSLocalizedString("diaperLog.logDiaper", comment: "")) {
                            var ok = false
                            if let record = editingRecord {
                                ok = vm.updateDiaper(record, type: diaperType, notes: notes, timestamp: timestamp)
                                appState.showToast(ok ? NSLocalizedString("diaperLog.updated", comment: "") : NSLocalizedString("diaperLog.saveFailed", comment: ""),
                                                   icon: ok ? "pencil.circle.fill" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blDiaper : .red)
                            } else {
                                ok = vm.logDiaper(type: diaperType, notes: notes, timestamp: timestamp)
                                appState.showToast(ok ? NSLocalizedString("diaperLog.logged", comment: "") : NSLocalizedString("diaperLog.saveFailed", comment: ""),
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
            .navigationTitle(isEditing ? NSLocalizedString("diaperLog.editTitle", comment: "") : NSLocalizedString("diaperLog.title", comment: ""))
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
                    .foregroundColor(.blDiaper)
                }
            }
            .onAppear {
                populateFromRecord()
                // Apply initial date for retroactive logging (only when creating new records)
                if !isEditing, let initialDate {
                    timestamp = initialDate
                }
            }
        }
    }

    private func populateFromRecord() {
        guard let r = editingRecord else { return }
        diaperType = DiaperType(rawValue: r.diaperType ?? "") ?? .wet
        notes = r.notes ?? ""
        timestamp = r.timestamp ?? Date()
    }
}
