import SwiftUI

struct SleepLogView: View {
    @ObservedObject var vm: TrackViewModel
    @Environment(\.dismiss) var dismiss

    /// When non-nil, we are editing an existing record
    var editingRecord: CDSleepRecord?

    @State private var startTime = Date().addingTimeInterval(-3600)
    @State private var endTime   = Date()
    @State private var location: SleepLocation = .crib
    @State private var notes = ""
    @State private var isOngoing = false

    private var isEditing: Bool { editingRecord != nil }

    private var duration: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }
    private var durationText: String {
        let h = duration / 60, m = duration % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {

                        // Ongoing toggle (only for new records)
                        if !isEditing {
                            Toggle(isOn: $isOngoing) {
                                Label("Baby is sleeping now", systemImage: "moon.zzz.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.blTextPrimary)
                            }
                            .tint(.blSleep)
                            .padding(16)
                            .background(Color.blSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        if !isOngoing {
                            // Duration summary
                            HStack {
                                Spacer()
                                VStack(spacing: 4) {
                                    Text(durationText)
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundColor(.blSleep)
                                    Text("sleep duration")
                                        .font(.system(size: 14))
                                        .foregroundColor(.blTextSecondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)

                            // Start time
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Start Time", systemImage: "moon.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.blTextSecondary)
                                DatePicker("", selection: $startTime, in: ...endTime, displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .tint(.blSleep)
                                    .labelsHidden()
                            }

                            // End time
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Wake Time", systemImage: "sun.and.horizon.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.blTextSecondary)
                                DatePicker("", selection: $endTime, in: startTime..., displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .tint(.blSleep)
                                    .labelsHidden()
                            }
                        }

                        // Location
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Location", systemImage: "location.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(SleepLocation.allCases, id: \.self) { loc in
                                    Button {
                                        withAnimation(.spring(response: 0.3)) { location = loc }
                                    } label: {
                                        VStack(spacing: 4) {
                                            Text(loc.icon).font(.system(size: 22))
                                            Text(loc.displayName)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(location == loc ? .white : .blTextPrimary)
                                                .multilineTextAlignment(.center)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(location == loc ? Color.blSleep : Color.blSurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Notes
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Notes", systemImage: "note.text")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextSecondary)
                            TextField("Add a note…", text: $notes, axis: .vertical)
                                .lineLimit(2...4)
                                .padding(14)
                                .background(Color.blSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Button(isEditing ? "Update Sleep" : (isOngoing ? "Start Sleep Timer" : "Log Sleep")) {
                            if let record = editingRecord {
                                vm.updateSleep(record, start: startTime, end: endTime, location: location, notes: notes)
                            } else if isOngoing {
                                _ = vm.startSleep(location: location, notes: notes)
                            } else {
                                vm.logSleep(start: startTime, end: endTime, location: location, notes: notes)
                            }
                            dismiss()
                        }
                        .buttonStyle(BLPrimaryButton(color: .blSleep))
                        .padding(.top, 8)
                    }
                    .padding(24)
                }
            }
            .navigationTitle(isEditing ? "Edit Sleep" : "Log Sleep")
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
        startTime = r.startTime ?? Date().addingTimeInterval(-3600)
        endTime = r.endTime ?? Date()
        location = SleepLocation(rawValue: r.location ?? "") ?? .crib
        notes = r.notes ?? ""
        isOngoing = false
    }
}
