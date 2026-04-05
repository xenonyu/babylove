import SwiftUI
import CoreData

struct FeedingLogView: View {
    @ObservedObject var vm: TrackViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    /// When non-nil, we are editing an existing record
    var editingRecord: CDFeedingRecord?

    @State private var feedType: FeedType = .breast
    @State private var side: BreastSide = .left
    @State private var duration: Double = 10
    @State private var amount: Double = 0
    @State private var notes = ""
    @State private var timestamp = Date()
    @State private var showTimePicker = false
    @State private var isTimerMode = false
    @State private var lastSideUsed: BreastSide?
    @State private var didAutoSuggestSide = false

    private var isEditing: Bool { editingRecord != nil }
    private var unit: MeasurementUnit { appState.measurementUnit }
    /// Max amount in display unit (300 ml ~ 10 oz)
    private var maxAmount: Double { unit == .metric ? 300 : 10 }
    private var amountStep: Double { unit == .metric ? 5 : 0.5 }

    /// Whether the current feed type supports timer mode
    private var supportsTimer: Bool {
        feedType == .breast || feedType == .pump
    }

    /// Dynamic button label based on mode
    private var buttonLabel: String {
        if isEditing { return "Update Feeding" }
        if isTimerMode && supportsTimer { return "Start Feeding Timer" }
        return "Log Feeding"
    }

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
                                        Haptic.selection()
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
                                    .accessibilityLabel("\(t.displayName) feeding")
                                    .accessibilityAddTraits(feedType == t ? .isSelected : [])
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
                                            Haptic.selection()
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
                                        .accessibilityLabel("\(s.displayName) side")
                                        .accessibilityAddTraits(side == s ? .isSelected : [])
                                    }
                                }

                                // Smart side suggestion hint
                                if !isEditing, let lastSide = lastSideUsed, lastSide != .both {
                                    HStack(spacing: 6) {
                                        Image(systemName: "brain.head.profile")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.blFeeding)
                                        Text("Last: \(lastSide.displayName)")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.blTextSecondary)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.blTextTertiary)
                                        Text("Suggested: \(side.displayName)")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.blFeeding)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.blFeeding.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }

                            // Timer mode toggle (only for new records)
                            if !isEditing {
                                Toggle(isOn: $isTimerMode) {
                                    Label("Use Timer", systemImage: "timer")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.blTextPrimary)
                                }
                                .tint(.blFeeding)
                                .padding(16)
                                .background(Color.blSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            // Duration (manual mode only)
                            if !isTimerMode {
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
                                        .accessibilityLabel("Duration")
                                        .accessibilityValue("\(Int(duration)) minutes")
                                }
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
                                    .accessibilityLabel("Amount")
                                    .accessibilityValue(unit == .metric ? "\(Int(amount)) milliliters" : String(format: "%.1f ounces", amount))
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
                                        .foregroundColor(.blFeeding)
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
                                DatePicker("Feeding time", selection: $timestamp, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .tint(.blFeeding)
                                    .labelsHidden()
                                    .accessibilityLabel("Feeding time")
                                    .transition(.opacity.combined(with: .move(edge: .top)))
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

                        Button(buttonLabel) {
                            let hasDuration = feedType == .breast || feedType == .pump
                            let hasAmount = feedType == .formula || feedType == .pump || feedType == .solid
                            // Zero out irrelevant fields to avoid stale data across type switches
                            let amountML = hasAmount ? unit.volumeToML(amount) : 0
                            var ok = false
                            if let record = editingRecord {
                                ok = vm.updateFeeding(
                                    record,
                                    type: feedType,
                                    side: hasDuration ? side : nil,
                                    durationMinutes: hasDuration ? Int(duration) : 0,
                                    amountML: amountML,
                                    notes: notes,
                                    timestamp: timestamp
                                )
                                appState.showToast(ok ? "Feeding updated" : "Save failed — try again",
                                                   icon: ok ? "pencil.circle.fill" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blFeeding : .red)
                            } else if isTimerMode && supportsTimer {
                                // Start a feeding timer (ongoing record)
                                ok = vm.startFeeding(
                                    type: feedType,
                                    side: side,
                                    notes: notes,
                                    timestamp: timestamp
                                )
                                appState.showToast(ok ? "Feeding timer started" : "Save failed — try again",
                                                   icon: ok ? "timer" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blFeeding : .red)
                            } else {
                                ok = vm.logFeeding(
                                    type: feedType,
                                    side: hasDuration ? side : nil,
                                    durationMinutes: hasDuration ? Int(duration) : 0,
                                    amountML: amountML,
                                    notes: notes,
                                    timestamp: timestamp
                                )
                                appState.showToast(ok ? "Feeding logged" : "Save failed — try again",
                                                   icon: ok ? "drop.fill" : "exclamationmark.triangle.fill",
                                                   color: ok ? .blFeeding : .red)
                            }
                            if ok { Haptic.success(); dismiss() } else { Haptic.error() }
                        }
                        .buttonStyle(BLPrimaryButton(color: .blFeeding))
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)
                        .padding(.top, 8)

                        if isTimerMode && supportsTimer && !isEditing {
                            Text("Timer will run on the home screen — end it when done")
                                .font(.system(size: 13))
                                .foregroundColor(.blTextSecondary)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                        } else if !canSave {
                            Text("Set the amount before saving")
                                .font(.system(size: 13))
                                .foregroundColor(.blTextSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(24)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Edit Feeding" : "Log Feeding")
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
                    .foregroundColor(.blFeeding)
                }
            }
            .onChange(of: feedType) { _, newType in
                let usesDuration = newType == .breast || newType == .pump
                let usesAmount = newType == .formula || newType == .pump || newType == .solid
                // Reset fields that are irrelevant to the new type
                if !usesDuration { duration = 10 }
                if !usesAmount { amount = 0 }
                // Disable timer mode for types that don't support it
                if !supportsTimer { isTimerMode = false }
            }
            .onAppear {
                populateFromRecord()
                if !isEditing { suggestNextSide() }
            }
        }
    }

    private func populateFromRecord() {
        guard let r = editingRecord else { return }
        feedType = FeedType(rawValue: r.feedType ?? "") ?? .breast
        side = BreastSide(rawValue: r.breastSide ?? "") ?? .left
        duration = Double(r.durationMinutes)
        amount = unit.volumeFromML(r.amountML)
        notes = r.notes ?? ""
        timestamp = r.timestamp ?? Date()
    }

    /// Fetch the last breast/pump feeding's side and auto-select the opposite
    private func suggestNextSide() {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<CDFeedingRecord> = CDFeedingRecord.fetchRequest()
        req.predicate = NSPredicate(format: "(feedType == %@ OR feedType == %@) AND breastSide != nil AND breastSide != %@",
                                    FeedType.breast.rawValue, FeedType.pump.rawValue, "")
        req.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        req.fetchLimit = 1

        guard let last = (try? ctx.fetch(req))?.first,
              let lastRaw = last.breastSide,
              let lastSide = BreastSide(rawValue: lastRaw) else { return }

        lastSideUsed = lastSide

        // Auto-select opposite side
        let suggested: BreastSide
        switch lastSide {
        case .left:  suggested = .right
        case .right: suggested = .left
        case .both:  suggested = .both
        }
        side = suggested
        didAutoSuggestSide = true
    }
}
