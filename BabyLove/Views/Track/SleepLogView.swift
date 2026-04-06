import SwiftUI
import CoreData

struct SleepLogView: View {
    @ObservedObject var vm: TrackViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    /// When non-nil, we are editing an existing record
    var editingRecord: CDSleepRecord?
    /// Optional initial date for the timestamp (used for retroactive logging from past dates)
    var initialDate: Date? = nil

    @State private var startTime = Date().addingTimeInterval(-3600)
    @State private var endTime   = Date()
    @State private var location: SleepLocation = .crib
    @State private var notes = ""
    @State private var isOngoing = false
    /// True when another sleep timer is already running (prevents duplicates)
    @State private var hasExistingOngoingSleep = false
    /// Whether the start time falls on a different calendar day than today
    private var isStartTimePastDay: Bool {
        !Calendar.current.isDateInToday(startTime)
    }

    private var isEditing: Bool { editingRecord != nil }

    /// Whether the form is valid for saving:
    /// - Ongoing mode: valid only if no other sleep timer is already running
    /// - Finished mode: endTime must be after startTime (duration > 0)
    private var canSave: Bool {
        if isOngoing {
            // Allow editing an existing ongoing record, but block creating a new one
            // when another timer is already running
            return isEditing || !hasExistingOngoingSleep
        }
        return duration > 0
    }

    private var duration: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }
    private var durationText: String {
        let h = duration / 60, m = duration % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
    private var ongoingDurationText: String {
        let mins = max(0, Int(Date().timeIntervalSince(startTime) / 60))
        let h = mins / 60, m = mins % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {

                        // Retroactive date banner — shown when logging to a past day
                        if isStartTimePastDay && !isEditing {
                            HStack(spacing: 10) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 16))
                                    .foregroundColor(.blSleep)
                                Text("Recording for \(startTime.formatted(date: .long, time: .omitted))")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.blTextPrimary)
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.blSleep.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.blSleep.opacity(0.2), lineWidth: 1)
                            )
                        }

                        // Ongoing toggle
                        Toggle(isOn: $isOngoing) {
                            Label(isEditing ? "Still sleeping" : "Baby is sleeping now",
                                  systemImage: "moon.zzz.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blTextPrimary)
                        }
                        .tint(.blSleep)
                        .padding(16)
                        .background(Color.blSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        // Warning: another sleep timer already running
                        if isOngoing && hasExistingOngoingSleep && !isEditing {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.blGrowth)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Sleep timer already running")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.blTextPrimary)
                                    Text("End the current sleep from the Home screen before starting a new one.")
                                        .font(.system(size: 13))
                                        .foregroundColor(.blTextSecondary)
                                }
                            }
                            .padding(14)
                            .background(Color.blGrowth.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.blGrowth.opacity(0.3), lineWidth: 1)
                            )
                        }

                        if isOngoing {
                            // Ongoing: show start time + live elapsed
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Fell Asleep", systemImage: "moon.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.blTextSecondary)
                                DatePicker("Fell asleep time", selection: $startTime, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .tint(.blSleep)
                                    .labelsHidden()
                                    .accessibilityLabel("Fell asleep time")
                            }

                            if isEditing {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 4) {
                                        Text(ongoingDurationText)
                                            .font(.system(size: 36, weight: .bold))
                                            .foregroundColor(.blSleep)
                                        Text("sleeping…")
                                            .font(.system(size: 14))
                                            .foregroundColor(.blTextSecondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                        } else {
                            // Finished: show duration + start/end pickers
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
                                DatePicker("Sleep start time", selection: $startTime, in: ...endTime, displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .tint(.blSleep)
                                    .labelsHidden()
                                    .accessibilityLabel("Sleep start time")
                            }

                            // End time
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Wake Time", systemImage: "sun.and.horizon.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.blTextSecondary)
                                DatePicker("Wake up time", selection: $endTime, in: startTime...Date(), displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .tint(.blSleep)
                                    .labelsHidden()
                                    .accessibilityLabel("Wake up time")
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
                                        Haptic.selection()
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
                                    .accessibilityLabel(loc.displayName)
                                    .accessibilityAddTraits(location == loc ? .isSelected : [])
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
                            var ok = false
                            if let record = editingRecord {
                                ok = vm.updateSleep(record, start: startTime, end: isOngoing ? nil : endTime, location: location, notes: notes)
                                appState.showToast(ok ? "Sleep updated" : "Save failed — try again",
                                                   icon: ok ? "pencil.circle.fill" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blSleep : .red)
                            } else if isOngoing {
                                ok = vm.startSleep(at: startTime, location: location, notes: notes)
                                appState.showToast(ok ? "Sleep timer started" : "Save failed — try again",
                                                   icon: ok ? "moon.zzz.fill" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blSleep : .red)
                            } else {
                                ok = vm.logSleep(start: startTime, end: endTime, location: location, notes: notes)
                                appState.showToast(ok ? "Sleep logged" : "Save failed — try again",
                                                   icon: ok ? "moon.zzz.fill" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blSleep : .red)
                            }
                            if ok { Haptic.success(); dismiss() } else { Haptic.error() }
                        }
                        .buttonStyle(BLPrimaryButton(color: .blSleep))
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)
                        .padding(.top, 8)

                        if !canSave && isOngoing && hasExistingOngoingSleep && !isEditing {
                            Text("A sleep timer is already active")
                                .font(.system(size: 13))
                                .foregroundColor(.blGrowth)
                                .frame(maxWidth: .infinity)
                        } else if !canSave && !isOngoing {
                            Text("End time must be after start time")
                                .font(.system(size: 13))
                                .foregroundColor(.blTextSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(24)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Edit Sleep" : "Log Sleep")
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
                    .foregroundColor(.blSleep)
                }
            }
            .onAppear {
                populateFromRecord()
                // Apply initial date for retroactive logging (only when creating new records)
                if !isEditing, let initialDate {
                    startTime = initialDate.addingTimeInterval(-3600)
                    endTime = initialDate
                }
                checkExistingOngoingSleep()
            }
            .onChange(of: isOngoing) { oldValue, newValue in
                // When toggling from ongoing → finished, snap endTime to now
                if oldValue == true && newValue == false {
                    endTime = Date()
                }
            }
        }
    }

    /// Check if another sleep record is already ongoing (endTime == nil).
    /// Excludes the record being edited (if any) to allow editing an ongoing sleep.
    private func checkExistingOngoingSleep() {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<CDSleepRecord> = CDSleepRecord.fetchRequest()
        req.predicate = NSPredicate(format: "endTime == nil")
        // When editing, we need to fetch at least 2 results so that if the first
        // result is the record being edited, we can still detect a second ongoing
        // sleep. With fetchLimit=1 the duplicate could be masked.
        req.fetchLimit = isEditing ? 2 : 1
        guard let results = try? ctx.fetch(req) else { return }
        // If editing an ongoing sleep, that record itself shouldn't count
        if let editing = editingRecord {
            hasExistingOngoingSleep = results.contains(where: { $0.objectID != editing.objectID })
        } else {
            hasExistingOngoingSleep = !results.isEmpty
        }
    }

    private func populateFromRecord() {
        guard let r = editingRecord else { return }
        startTime = r.startTime ?? Date().addingTimeInterval(-3600)
        endTime = r.endTime ?? Date()
        location = SleepLocation(rawValue: r.location ?? "") ?? .crib
        notes = r.notes ?? ""
        isOngoing = (r.endTime == nil)
    }
}
