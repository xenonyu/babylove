import SwiftUI
import CoreData

struct GrowthView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) var ctx
    @StateObject private var vm = TrackViewModel(context: PersistenceController.shared.container.viewContext)
    @State private var showLog = false
    @State private var selectedMetric: GrowthMetric = .weight
    @State private var recordToDelete: CDGrowthRecord?
    @State private var recordToEdit: CDGrowthRecord?
    @State private var showAllRecords = false

    @FetchRequest(
        entity: CDGrowthRecord.entity(),
        sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)]
    ) private var records: FetchedResults<CDGrowthRecord>

    enum GrowthMetric: String, CaseIterable {
        case weight = "Weight"
        case height = "Height"
        case head   = "Head"

        var localizedName: String {
            switch self {
            case .weight: return String(localized: "growth.weight")
            case .height: return String(localized: "growth.height")
            case .head:   return String(localized: "growth.head")
            }
        }

        /// Lowercase localized name for accessibility / chart labels
        var localizedAccessibilityName: String {
            switch self {
            case .weight: return String(localized: "growth.weightLabel")
            case .height: return String(localized: "growth.heightLabel")
            case .head:   return String(localized: "growth.headCircLabel")
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        // Metric picker
                        Picker(String(localized: "growth.title"), selection: $selectedMetric) {
                            ForEach(GrowthMetric.allCases, id: \.self) { m in
                                Text(m.localizedName).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)

                        // Measurement reminder nudge
                        if let reminder = measurementReminder {
                            measurementReminderCard(reminder)
                                .padding(.horizontal, 20)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Chart area
                        chartArea
                            .padding(.horizontal, 20)

                        // Records list
                        if !records.isEmpty {
                            VStack(spacing: 12) {
                                HStack {
                                    BLSectionHeader(title: String(localized: "growth.records"))
                                    Spacer()
                                    Text("\(records.count)")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.blTextTertiary)
                                }
                                .padding(.horizontal, 20)

                                let previewLimit = 10
                                let allReversed = Array(records.reversed())
                                let displayed = showAllRecords ? allReversed : Array(allReversed.prefix(previewLimit))

                                VStack(spacing: 0) {
                                    ForEach(Array(displayed.enumerated()), id: \.element.id) { index, r in
                                        growthRow(r)
                                            .contentShape(Rectangle())
                                            .onTapGesture { recordToEdit = r }
                                            .contextMenu {
                                                Button {
                                                    recordToEdit = r
                                                } label: {
                                                    Label(String(localized: "growth.edit"), systemImage: "pencil")
                                                }
                                                Button(role: .destructive) {
                                                    recordToDelete = r
                                                } label: {
                                                    Label(String(localized: "growth.delete"), systemImage: "trash")
                                                }
                                            }
                                        if index < displayed.count - 1 {
                                            Divider().padding(.leading, 56)
                                        }
                                    }

                                    // Show more / Show less toggle when there are more than previewLimit records
                                    if records.count > previewLimit {
                                        Divider().padding(.leading, 56)
                                        Button {
                                            Haptic.selection()
                                            withAnimation(.spring(response: 0.35)) {
                                                showAllRecords.toggle()
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                Text(showAllRecords ? String(localized: "growth.showLess") : String(localized: "growth.showAll \(records.count)"))
                                                    .font(.system(size: 14, weight: .medium))
                                                Image(systemName: showAllRecords ? "chevron.up" : "chevron.down")
                                                    .font(.system(size: 11, weight: .semibold))
                                            }
                                            .foregroundColor(.blGrowth)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .blCard()
                                .padding(.horizontal, 20)
                            }
                        } else {
                            emptyState
                        }

                        Spacer(minLength: 100)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle(String(localized: "growth.title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showLog = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.blGrowth)
                    }
                }
            }
        }
        .sheet(isPresented: $showLog) {
            GrowthLogView(vm: vm)
        }
        .sheet(item: $recordToEdit) { record in
            GrowthLogView(vm: vm, editingRecord: record)
        }
        .alert(String(localized: "growth.deleteRecord"), isPresented: Binding(
            get: { recordToDelete != nil },
            set: { if !$0 { recordToDelete = nil } }
        )) {
            Button(String(localized: "growth.cancel"), role: .cancel) { recordToDelete = nil }
            Button(String(localized: "growth.delete"), role: .destructive) {
                Haptic.warning()
                if let obj = recordToDelete {
                    let success = vm.deleteObject(obj, in: ctx)
                    if success {
                        withAnimation { /* row removed */ }
                        appState.showToast(String(localized: "growth.deleted"), icon: "trash.fill", color: .blGrowth)
                    } else {
                        Haptic.error()
                        appState.showToast(String(localized: "common.deleteFailed"), icon: "exclamationmark.triangle.fill", color: .red)
                    }
                }
                recordToDelete = nil
            }
        } message: {
            Text(String(localized: "growth.deleteConfirm"))
        }
    }

    // MARK: - Latest value helpers

    /// Find the latest record that has a non-zero value for the given metric.
    /// Falls back through all records (sorted ascending), checking from newest.
    private func latestRecord(for metric: GrowthMetric) -> CDGrowthRecord? {
        for record in records.reversed() {
            switch metric {
            case .weight: if record.weightKG > 0 { return record }
            case .height: if record.heightCM > 0 { return record }
            case .head:   if record.headCircumferenceCM > 0 { return record }
            }
        }
        return nil
    }

    /// Find the second-to-latest record that has a non-zero value for the given metric.
    /// Used to calculate the growth delta (change) between the two most recent measurements.
    private func previousRecord(for metric: GrowthMetric) -> CDGrowthRecord? {
        var found = 0
        for record in records.reversed() {
            let hasValue: Bool
            switch metric {
            case .weight: hasValue = record.weightKG > 0
            case .height: hasValue = record.heightCM > 0
            case .head:   hasValue = record.headCircumferenceCM > 0
            }
            if hasValue {
                found += 1
                if found == 2 { return record }
            }
        }
        return nil
    }

    /// Calculate the delta (change) between the latest and previous measurement in display units.
    /// Returns nil if there aren't two records to compare.
    private func metricDelta(for metric: GrowthMetric, unit: MeasurementUnit) -> Double? {
        guard let latest = latestRecord(for: metric),
              let previous = previousRecord(for: metric) else { return nil }
        let latestVal: Double
        let prevVal: Double
        switch metric {
        case .weight:
            latestVal = unit.weightFromKG(latest.weightKG)
            prevVal   = unit.weightFromKG(previous.weightKG)
        case .height:
            latestVal = unit.lengthFromCM(latest.heightCM)
            prevVal   = unit.lengthFromCM(previous.heightCM)
        case .head:
            latestVal = unit.lengthFromCM(latest.headCircumferenceCM)
            prevVal   = unit.lengthFromCM(previous.headCircumferenceCM)
        }
        let delta = latestVal - prevVal
        // Only show meaningful deltas (avoid -0.00 / +0.00 noise)
        guard abs(delta) >= 0.01 else { return nil }
        return delta
    }

    /// Number of days between the two most recent measurements for a given metric.
    /// Returns nil if there aren't two dated records to compare.
    private func deltaSpanDays(for metric: GrowthMetric) -> Int? {
        guard let latest = latestRecord(for: metric),
              let previous = previousRecord(for: metric),
              let latestDate = latest.date,
              let prevDate = previous.date else { return nil }
        let days = Calendar.current.dateComponents([.day], from: prevDate, to: latestDate).day ?? 0
        return days > 0 ? days : nil
    }

    /// Compact, human-readable span label (e.g. "3d", "2w", "1mo").
    private static func shortSpanLabel(_ days: Int) -> String {
        if days < 14 {
            return String(format: NSLocalizedString("growth.spanDays %lld", comment: ""), days)
        } else if days < 60 {
            let weeks = days / 7
            return String(format: NSLocalizedString("growth.spanWeeks %lld", comment: ""), weeks)
        } else {
            let months = days / 30
            return String(format: NSLocalizedString("growth.spanMonths %lld", comment: ""), months)
        }
    }

    /// Calculate the baby's WHO percentile for a given metric using the latest record.
    /// Returns nil if baby gender is .other, no data, or age out of WHO range.
    private func whoPercentile(for metric: GrowthMetric) -> Int? {
        guard let baby = appState.currentBaby, baby.gender != .other else { return nil }
        guard let record = latestRecord(for: metric), let recordDate = record.date else { return nil }

        let metricKey: String
        let rawValue: Double
        switch metric {
        case .weight:
            metricKey = "weight"
            rawValue = record.weightKG
        case .height:
            metricKey = "height"
            rawValue = record.heightCM
        case .head:
            metricKey = "head"
            rawValue = record.headCircumferenceCM
        }
        guard rawValue > 0 else { return nil }

        let ageMonths = recordDate.timeIntervalSince(baby.birthDate) / (30.4375 * 86400)
        guard ageMonths >= 0 && ageMonths <= 24 else { return nil }

        let table = WHOGrowthData.table(metric: metricKey, isBoy: baby.gender == .boy)
        guard let pctl = table.percentile(atMonth: ageMonths, value: rawValue) else { return nil }
        return Int(pctl.rounded())
    }

    // MARK: - Percentile Availability Hint

    /// Reason why WHO percentile cannot be calculated, if any
    private var percentileUnavailableReason: String? {
        guard !records.isEmpty else { return nil }
        // Already showing at least one percentile? No hint needed
        let hasAnyPercentile = GrowthMetric.allCases.contains { whoPercentile(for: $0) != nil }
        if hasAnyPercentile { return nil }

        // Check specific reasons
        if let baby = appState.currentBaby {
            if baby.gender == .other {
                return String(localized: "growth.percentileHintGender")
            }
            let ageMonths = Date().timeIntervalSince(baby.birthDate) / (30.4375 * 86400)
            if ageMonths > 24 {
                return String(localized: "growth.percentileHintAge")
            }
        } else {
            return String(localized: "growth.percentileHintNoBaby")
        }
        return nil
    }

    // MARK: - Measurement Reminder

    /// Reminder info: days since last measurement and recommended interval
    private struct MeasurementReminderInfo {
        let daysSince: Int
        let recommendedInterval: Int
        let message: String
        let icon: String
    }

    /// Returns a reminder if it's been too long since the last measurement, based on baby's age.
    /// Newborns (0-3mo): every 7 days, Infants (3-12mo): every 14 days, Toddlers (12mo+): every 30 days.
    private var measurementReminder: MeasurementReminderInfo? {
        // Only show when there are records and a baby profile
        guard !records.isEmpty, let baby = appState.currentBaby else { return nil }

        // Find the latest record date
        guard let latestDate = records.last?.date else { return nil }
        let daysSince = Calendar.current.dateComponents([.day], from: latestDate, to: Date()).day ?? 0

        // Determine recommended interval based on baby's age
        let ageMonths = baby.ageInMonths
        let interval: Int
        let ageGroup: String
        if ageMonths < 3 {
            interval = 7
            ageGroup = String(localized: "growth.reminder.newborn")
        } else if ageMonths < 12 {
            interval = 14
            ageGroup = String(localized: "growth.reminder.infant")
        } else {
            interval = 30
            ageGroup = String(localized: "growth.reminder.toddler")
        }

        guard daysSince >= interval else { return nil }

        let message: String
        let icon: String
        if daysSince >= interval * 2 {
            // Very overdue
            message = String(format: NSLocalizedString("growth.reminder.overdue %lld", comment: ""), daysSince)
            icon = "exclamationmark.circle.fill"
        } else {
            // Gentle reminder
            message = String(format: NSLocalizedString("growth.reminder.due %lld %@", comment: ""), daysSince, ageGroup)
            icon = "clock.badge.exclamationmark"
        }

        return MeasurementReminderInfo(daysSince: daysSince, recommendedInterval: interval, message: message, icon: icon)
    }

    @ViewBuilder
    private func measurementReminderCard(_ info: MeasurementReminderInfo) -> some View {
        Button {
            Haptic.selection()
            showLog = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blGrowth.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: info.icon)
                        .font(.system(size: 18))
                        .foregroundColor(.blGrowth)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "growth.reminder.title"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blTextPrimary)
                    Text(info.message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blTextSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blGrowth)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.blGrowth.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.blGrowth.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "growth.reminder.a11y.label"))
        .accessibilityHint(String(format: NSLocalizedString("growth.reminder.a11y.hint %lld", comment: ""), info.daysSince))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Chart Area
    private var chartArea: some View {
        VStack(spacing: 16) {
            // Latest measurements overview — shows most recent non-zero value for each metric
            if !records.isEmpty {
                latestMeasurementsCard

                // Hint explaining why WHO percentile isn't available
                if let reason = percentileUnavailableReason {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundColor(.blGrowth.opacity(0.7))
                        Text(reason)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.blTextTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // Growth chart with WHO percentile curves
            if !records.isEmpty {
                SimpleLineChart(
                    records: Array(records),
                    metric: selectedMetric,
                    unit: appState.measurementUnit,
                    baby: appState.currentBaby
                )
                .frame(height: 260)
                .blCard()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(chartAccessibilityLabel)
                .accessibilityHint(String(localized: "growth.chartTapHint"))
            }
        }
    }

    /// VoiceOver summary for the growth chart
    private var chartAccessibilityLabel: String {
        let unit = appState.measurementUnit
        let dataRecords = records.filter { rawValueForMetric($0) > 0 }
        let metricLocalized = selectedMetric.localizedName
        guard !dataRecords.isEmpty else {
            return String(localized: "growth.chartNoData \(metricLocalized)")
        }
        let count = dataRecords.count
        if let first = dataRecords.first, let last = dataRecords.last {
            let firstVal = displayValueForMetric(first, unit: unit)
            let lastVal = displayValueForMetric(last, unit: unit)
            let unitLabel = selectedMetric == .weight ? unit.weightLabel : unit.heightLabel
            var label = String(localized: "growth.chartLabel \(metricLocalized) \(count)")
            if count > 1 {
                label += ", \(String(format: selectedMetric == .weight ? "%.2f" : "%.1f", firstVal)) → \(String(format: selectedMetric == .weight ? "%.2f" : "%.1f", lastVal)) \(unitLabel)"
            } else {
                label += ", \(String(format: selectedMetric == .weight ? "%.2f" : "%.1f", lastVal)) \(unitLabel)"
            }
            if let pctl = whoPercentile(for: selectedMetric) {
                label += ", \(String(localized: "growth.percentile \(pctl)"))"
            }
            return label
        }
        return String(localized: "growth.chartNoData \(metricLocalized)")
    }

    /// Raw value in storage units for a record given the selected metric
    private func rawValueForMetric(_ r: CDGrowthRecord) -> Double {
        switch selectedMetric {
        case .weight: return r.weightKG
        case .height: return r.heightCM
        case .head:   return r.headCircumferenceCM
        }
    }

    /// Display value for a record given the selected metric and unit
    private func displayValueForMetric(_ r: CDGrowthRecord, unit: MeasurementUnit) -> Double {
        switch selectedMetric {
        case .weight: return unit.weightFromKG(r.weightKG)
        case .height: return unit.lengthFromCM(r.heightCM)
        case .head:   return unit.lengthFromCM(r.headCircumferenceCM)
        }
    }

    private var latestMeasurementsCard: some View {
        let unit = appState.measurementUnit
        let latestWeight = latestRecord(for: .weight)
        let latestHeight = latestRecord(for: .height)
        let latestHead   = latestRecord(for: .head)
        let weightPctl = whoPercentile(for: .weight)
        let heightPctl = whoPercentile(for: .height)
        let headPctl   = whoPercentile(for: .head)
        let weightDelta = metricDelta(for: .weight, unit: unit)
        let heightDelta = metricDelta(for: .height, unit: unit)
        let headDelta   = metricDelta(for: .head, unit: unit)
        let weightSpan  = deltaSpanDays(for: .weight)
        let heightSpan  = deltaSpanDays(for: .height)
        let headSpan    = deltaSpanDays(for: .head)

        return HStack(spacing: 0) {
            // Weight
            metricColumn(
                value: latestWeight.map { String(format: "%.2f", unit.weightFromKG($0.weightKG)) },
                label: unit.weightLabel,
                icon: "scalemass.fill",
                isSelected: selectedMetric == .weight,
                percentile: weightPctl,
                delta: weightDelta,
                deltaFormat: "%.2f",
                deltaSpanDays: weightSpan,
                measureDate: latestWeight?.date
            ) { selectedMetric = .weight }

            dividerLine

            // Height
            metricColumn(
                value: latestHeight.map { String(format: "%.1f", unit.lengthFromCM($0.heightCM)) },
                label: unit.heightLabel,
                icon: "ruler.fill",
                isSelected: selectedMetric == .height,
                percentile: heightPctl,
                delta: heightDelta,
                deltaFormat: "%.1f",
                deltaSpanDays: heightSpan,
                measureDate: latestHeight?.date
            ) { selectedMetric = .height }

            dividerLine

            // Head
            metricColumn(
                value: latestHead.map { String(format: "%.1f", unit.lengthFromCM($0.headCircumferenceCM)) },
                label: String(localized: "growth.head"),
                icon: "circle.dashed",
                isSelected: selectedMetric == .head,
                percentile: headPctl,
                delta: headDelta,
                deltaFormat: "%.1f",
                deltaSpanDays: headSpan,
                measureDate: latestHead?.date
            ) { selectedMetric = .head }
        }
        .padding(.vertical, 16)
        .blCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "growth.latestMeasurements"))
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.blSurface)
            .frame(width: 1, height: 54)
    }

    private func metricColumn(value: String?, label: String, icon: String, isSelected: Bool, percentile: Int? = nil, delta: Double? = nil, deltaFormat: String = "%.1f", deltaSpanDays: Int? = nil, measureDate: Date? = nil, action: @escaping () -> Void) -> some View {
        Button(action: {
            Haptic.selection()
            withAnimation(.spring(response: 0.3)) { action() }
        }) {
            VStack(spacing: 4) {
                if let value {
                    Text(value)
                        .font(.system(size: isSelected ? 26 : 20, weight: .bold))
                        .foregroundColor(isSelected ? .blGrowth : .blTextSecondary)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(.blTextTertiary)
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .blGrowth : .blTextTertiary)

                // Growth delta from previous measurement (e.g. "+0.30 · 14d")
                if let delta {
                    let sign = delta > 0 ? "+" : ""
                    let deltaText = "\(sign)\(String(format: deltaFormat, delta))"
                    let spanText = deltaSpanDays.map { " · \(Self.shortSpanLabel($0))" } ?? ""
                    HStack(spacing: 2) {
                        Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 8, weight: .bold))
                        Text("\(deltaText)\(spanText)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(delta > 0 ? .blTeal : .blPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }

                // WHO percentile badge
                if let pctl = percentile {
                    Text("P\(pctl)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(percentileColor(pctl))
                        )
                }

                // Measurement date (e.g. "Apr 3" or "Today")
                if let date = measureDate {
                    Text(Self.shortMeasureDate(date))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.blTextTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metricAccessibilityLabel(value: value, label: label, percentile: percentile, delta: delta, deltaFormat: deltaFormat, deltaSpanDays: deltaSpanDays, measureDate: measureDate))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(String(localized: "growth.viewChart \(label)"))
    }

    /// Build a comprehensive VoiceOver label for a metric column
    private func metricAccessibilityLabel(value: String?, label: String, percentile: Int?, delta: Double? = nil, deltaFormat: String = "%.1f", deltaSpanDays: Int? = nil, measureDate: Date?) -> String {
        var parts: [String] = [label]
        if let value {
            parts.append(value)
        } else {
            parts.append(String(localized: "growth.noData"))
        }
        if let delta {
            let sign = delta > 0 ? "+" : ""
            let formatted = "\(sign)\(String(format: deltaFormat, delta))"
            var deltaLabel = String(format: NSLocalizedString("growth.a11y.delta %@", comment: ""), formatted)
            if let days = deltaSpanDays {
                deltaLabel += " \(String(format: NSLocalizedString("growth.a11y.inDays %lld", comment: ""), days))"
            }
            parts.append(deltaLabel)
        }
        if let pctl = percentile {
            let range = percentileRangeDescription(pctl)
            parts.append("\(String(localized: "growth.percentile \(pctl)")), \(range)")
        }
        if let date = measureDate {
            parts.append(String(localized: "growth.measured \(Self.shortMeasureDate(date))"))
        }
        return parts.joined(separator: ", ")
    }

    /// Human-readable description of what a percentile range means
    private func percentileRangeDescription(_ pctl: Int) -> String {
        if pctl < 3 || pctl > 97 { return String(localized: "growth.outsideRange") }
        if pctl < 15 || pctl > 85 { return String(localized: "growth.worthMonitoring") }
        return String(localized: "growth.healthyRange")
    }

    /// Short date text for measurement date: "Today", "Yesterday", or "Apr 3"
    private static func shortMeasureDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "growth.today") }
        if cal.isDateInYesterday(date) { return String(localized: "growth.yesterday") }
        return BLDateFormatters.monthDay.string(from: date)
    }

    /// Color coding for percentile badges: green for normal, amber for watch, red for concern
    private func percentileColor(_ pctl: Int) -> Color {
        if pctl < 3 || pctl > 97 { return .blPrimary }       // Outside normal — coral/alert
        if pctl < 15 || pctl > 85 { return .blGrowth }       // Worth watching — amber
        return .blTeal                                         // Healthy range — teal
    }

    private func growthRow(_ r: CDGrowthRecord) -> some View {
        let unit = appState.measurementUnit
        let baby = appState.currentBaby
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.blGrowth.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.blGrowth)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(r.date.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.blTextPrimary)
                    // Baby's age at this measurement
                    if let baby, let date = r.date {
                        Text(baby.ageText(at: date))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.blGrowth)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blGrowth.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 10) {
                    if r.weightKG > 0 {
                        Text("\(String(format: "%.2f", unit.weightFromKG(r.weightKG))) \(unit.weightLabel)")
                            .font(.system(size: 13))
                            .foregroundColor(.blTextSecondary)
                    }
                    if r.heightCM > 0 {
                        Text("\(String(format: "%.1f", unit.lengthFromCM(r.heightCM))) \(unit.heightLabel)")
                            .font(.system(size: 13))
                            .foregroundColor(.blTextSecondary)
                    }
                    if r.headCircumferenceCM > 0 {
                        Text("\(String(localized: "growth.hc")) \(String(format: "%.1f", unit.lengthFromCM(r.headCircumferenceCM))) \(unit.heightLabel)")
                            .font(.system(size: 13))
                            .foregroundColor(.blTextSecondary)
                    }
                }
                // Notes preview
                if let notes = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blTextTertiary)
                        Text(notes)
                            .font(.system(size: 12))
                            .foregroundColor(.blTextTertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(growthRowAccessibilityLabel(r, unit: unit, baby: baby))
        .accessibilityHint(NSLocalizedString("a11y.longPressEditDelete", comment: ""))
    }

    private func growthRowAccessibilityLabel(_ r: CDGrowthRecord, unit: MeasurementUnit, baby: Baby?) -> String {
        var parts: [String] = []
        if let date = r.date {
            parts.append(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))
        }
        if let baby, let date = r.date {
            parts.append(baby.ageText(at: date))
        }
        if r.weightKG > 0 {
            parts.append("\(String(localized: "growth.weightLabel")) \(String(format: "%.2f", unit.weightFromKG(r.weightKG))) \(unit.weightLabel)")
        }
        if r.heightCM > 0 {
            parts.append("\(String(localized: "growth.heightLabel")) \(String(format: "%.1f", unit.lengthFromCM(r.heightCM))) \(unit.heightLabel)")
        }
        if r.headCircumferenceCM > 0 {
            parts.append("\(String(localized: "growth.headCircLabel")) \(String(format: "%.1f", unit.lengthFromCM(r.headCircumferenceCM))) \(unit.heightLabel)")
        }
        if let notes = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            parts.append(String(format: NSLocalizedString("a11y.note %@", comment: ""), notes))
        }
        return parts.joined(separator: ", ")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(.blGrowth.opacity(0.4))
            Text(String(localized: "growth.noRecords"))
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.blTextSecondary)
            Text(String(localized: "growth.tapToAdd"))
                .font(.system(size: 14))
                .foregroundColor(.blTextTertiary)
                .multilineTextAlignment(.center)
            Button(String(localized: "growth.addMeasurement")) { showLog = true }
                .buttonStyle(BLPrimaryButton(color: .blGrowth))
                .frame(width: 200)
        }
        .padding(40)
    }
}

// MARK: - Simple Line Chart with WHO Percentile Curves
struct SimpleLineChart: View {
    let records: [CDGrowthRecord]
    let metric: GrowthView.GrowthMetric
    var unit: MeasurementUnit = .metric
    var baby: Baby? = nil

    /// Index of the data point currently selected for inspection
    @State private var selectedPointIndex: Int?

    /// Left margin reserved for Y-axis labels
    private let yAxisWidth: CGFloat = 40
    /// Bottom margin reserved for X-axis labels
    private let xAxisHeight: CGFloat = 24

    /// Pairs of (ageInMonths, value) filtered to non-zero values
    private func dataPoints() -> [(age: Double, value: Double, date: Date)] {
        guard let birthDate = baby?.birthDate else {
            // Fallback: use index-based if no baby
            return records.enumerated().compactMap { i, r -> (Double, Double, Date)? in
                let v = rawValue(for: r)
                guard v > 0, let d = r.date else { return nil }
                return (Double(i), v, d)
            }
        }
        return records.compactMap { r -> (Double, Double, Date)? in
            let v = rawValue(for: r)
            guard v > 0, let d = r.date else { return nil }
            let ageMonths = d.timeIntervalSince(birthDate) / (30.4375 * 86400)
            return (max(0, ageMonths), v, d)
        }
    }

    /// Get raw value in storage units (kg/cm) for WHO comparison
    private func rawValue(for r: CDGrowthRecord) -> Double {
        switch metric {
        case .weight: return r.weightKG
        case .height: return r.heightCM
        case .head:   return r.headCircumferenceCM
        }
    }

    /// Convert storage value to display value
    private func displayValue(_ raw: Double) -> Double {
        switch metric {
        case .weight: return unit.weightFromKG(raw)
        case .height, .head: return unit.lengthFromCM(raw)
        }
    }

    /// Icon shown in empty chart state for each metric
    private var metricEmptyIcon: String {
        switch metric {
        case .weight: return "scalemass"
        case .height: return "ruler"
        case .head:   return "circle.dashed"
        }
    }

    private var unitLabel: String {
        switch metric {
        case .weight: return unit.weightLabel
        case .height, .head: return unit.heightLabel
        }
    }

    private func formatValue(_ v: Double) -> String {
        metric == .weight ? String(format: "%.1f", v) : String(format: "%.0f", v)
    }

    /// Whether WHO curves should be shown
    private var showWHO: Bool {
        baby != nil && baby?.gender != .other
    }

    /// WHO table for current metric + gender
    private var whoTable: WHOGrowthTable? {
        guard let baby = baby, baby.gender != .other else { return nil }
        let metricKey: String
        switch metric {
        case .weight: metricKey = "weight"
        case .height: metricKey = "height"
        case .head:   metricKey = "head"
        }
        return WHOGrowthData.table(metric: metricKey, isBoy: baby.gender == .boy)
    }

    /// Percentiles to draw — outer bands + median
    private let displayPercentiles: [WHOPercentile] = [.p3, .p15, .p50, .p85, .p97]

    var body: some View {
        let data = dataPoints()
        guard !data.isEmpty else {
            return AnyView(
                VStack(spacing: 8) {
                    Image(systemName: metricEmptyIcon)
                        .font(.system(size: 28))
                        .foregroundColor(.blGrowth.opacity(0.35))
                    Text(String(localized: "growth.noDataYet \(metric.localizedName)"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blTextSecondary)
                    Text(String(localized: "growth.addToSeeChart \(metric.localizedName)"))
                        .font(.system(size: 12))
                        .foregroundColor(.blTextTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }

        // Determine chart bounds
        let rawValues = data.map(\.value)
        guard let ageMin = data.map(\.age).min(),
              let ageMax = data.map(\.age).max() else {
            return AnyView(
                Text(String(localized: "growth.notEnoughData"))
                    .font(.system(size: 14))
                    .foregroundColor(.blTextTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }

        // If WHO available, expand Y range to include percentile bounds
        var allValues = rawValues
        if let table = whoTable {
            let ageFloor = Int(ageMin)
            let ageCeil = min(Int(ceil(ageMax)), table.maxMonth)
            for m in ageFloor...ageCeil {
                if let lo = table.value(atMonth: Double(m), percentile: .p3) { allValues.append(lo) }
                if let hi = table.value(atMonth: Double(m), percentile: .p97) { allValues.append(hi) }
            }
        }

        guard let rawMin = allValues.min(),
              let rawMax = allValues.max() else {
            return AnyView(
                Text(String(localized: "growth.notEnoughData"))
                    .font(.system(size: 14))
                    .foregroundColor(.blTextTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }
        // Ensure a minimum range to prevent division by zero when all values are identical
        let naturalPadding = (rawMax - rawMin) * 0.08
        let safePadding = max(naturalPadding, rawMax * 0.05, 0.5)
        let chartMin = rawMin - safePadding
        let chartMax = rawMax + safePadding
        let chartRange = chartMax - chartMin  // Always > 0

        // Age range for X axis — for a single data point, show context window around it
        let agePadding: Double
        if ageMax - ageMin < 0.01 {
            // Single point: show ±2 months context so WHO curves are visible
            agePadding = 2.0
        } else {
            agePadding = max((ageMax - ageMin) * 0.05, 0.5)
        }
        let xMin = max(0, ageMin - agePadding)
        let xMax = ageMax + agePadding
        let xRange = xMax - xMin  // Always > 0 due to agePadding >= 0.5

        // Y-axis ticks in display units
        let tickCount = 4
        let yTicks = (0..<tickCount).map { i in
            chartMin + chartRange * Double(i) / Double(tickCount - 1)
        }

        return AnyView(
            VStack(spacing: 0) {
                // Header: unit + WHO legend
                HStack(spacing: 6) {
                    Text(unitLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.blTextTertiary)
                    Spacer()
                    if showWHO {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.blTeal.opacity(0.25))
                                .frame(width: 12, height: 8)
                            Text(String(localized: "growth.who"))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.blTextTertiary)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)

                HStack(alignment: .top, spacing: 0) {
                    // Y-axis labels (display units)
                    GeometryReader { geo in
                        let h = geo.size.height
                        ForEach(Array(yTicks.enumerated()), id: \.offset) { _, tick in
                            let yFrac = CGFloat((tick - chartMin) / chartRange)
                            let y = h - h * yFrac
                            Text(formatValue(displayValue(tick)))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.blTextTertiary)
                                .frame(width: yAxisWidth - 4, alignment: .trailing)
                                .position(x: (yAxisWidth - 4) / 2, y: y)
                        }
                    }
                    .frame(width: yAxisWidth)

                    // Chart area
                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height

                        ZStack {
                            // Background tap to dismiss tooltip
                            Color.clear.contentShape(Rectangle())
                                .onTapGesture {
                                    if selectedPointIndex != nil {
                                        withAnimation(.spring(response: 0.25)) {
                                            selectedPointIndex = nil
                                        }
                                    }
                                }

                            // Grid lines
                            ForEach(Array(yTicks.enumerated()), id: \.offset) { _, tick in
                                let y = h - h * CGFloat((tick - chartMin) / chartRange)
                                Path { p in
                                    p.move(to: CGPoint(x: 0, y: y))
                                    p.addLine(to: CGPoint(x: w, y: y))
                                }
                                .stroke(Color.blTextTertiary.opacity(0.12), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
                            }

                            // WHO percentile bands
                            if let table = whoTable {
                                // Shaded band: P3–P97 (outer)
                                whoFillBand(table: table, lower: .p3, upper: .p97,
                                            color: Color.blTeal.opacity(0.08),
                                            w: w, h: h, chartMin: chartMin, chartRange: chartRange,
                                            xMin: xMin, xRange: xRange)

                                // Shaded band: P15–P85 (healthy range)
                                whoFillBand(table: table, lower: .p15, upper: .p85,
                                            color: Color.blTeal.opacity(0.10),
                                            w: w, h: h, chartMin: chartMin, chartRange: chartRange,
                                            xMin: xMin, xRange: xRange)

                                // Percentile lines
                                ForEach(Array(displayPercentiles.enumerated()), id: \.offset) { _, pctl in
                                    whoLine(table: table, percentile: pctl,
                                            w: w, h: h, chartMin: chartMin, chartRange: chartRange,
                                            xMin: xMin, xRange: xRange)
                                }

                                // Percentile labels on right edge
                                ForEach(Array(displayPercentiles.enumerated()), id: \.offset) { _, pctl in
                                    if let val = table.value(atMonth: xMax, percentile: pctl) {
                                        let y = h - h * CGFloat((val - chartMin) / chartRange)
                                        Text(pctl.label)
                                            .font(.system(size: 7, weight: .medium))
                                            .foregroundColor(.blTeal.opacity(0.7))
                                            .position(x: w - 14, y: max(6, min(h - 6, y - 8)))
                                    }
                                }
                            }

                            // Baby's data: gradient fill
                            let points = data.map { dp in
                                CGPoint(
                                    x: w * CGFloat((dp.age - xMin) / xRange),
                                    y: h - h * CGFloat((dp.value - chartMin) / chartRange)
                                )
                            }

                            if let first = points.first, let last = points.last {
                                // Only draw fill and line when we have 2+ points
                                if points.count > 1 {
                                    Path { p in
                                        p.move(to: CGPoint(x: first.x, y: h))
                                        points.forEach { p.addLine(to: $0) }
                                        p.addLine(to: CGPoint(x: last.x, y: h))
                                        p.closeSubpath()
                                    }
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blGrowth.opacity(0.25), Color.blGrowth.opacity(0.02)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )

                                    // Baby's line
                                    Path { p in
                                        p.move(to: first)
                                        points.dropFirst().forEach { p.addLine(to: $0) }
                                    }
                                    .stroke(Color.blGrowth, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                                }

                                // Dots + value labels (tap to inspect)
                                ForEach(0..<points.count, id: \.self) { i in
                                    let pt = points[i]
                                    let isSelected = selectedPointIndex == i

                                    // Value label above point (dimmed when another point is inspected)
                                    if selectedPointIndex == nil || isSelected {
                                        Text(formatValue(displayValue(data[i].value)))
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundColor(.blGrowth)
                                            .position(x: pt.x, y: pt.y - 12)
                                    }

                                    // Data point dot (enlarged when selected)
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: isSelected ? 13 : 9, height: isSelected ? 13 : 9)
                                        .position(pt)
                                    Circle()
                                        .fill(Color.blGrowth)
                                        .frame(width: isSelected ? 9 : 6, height: isSelected ? 9 : 6)
                                        .position(pt)

                                    // Invisible larger tap target
                                    Circle()
                                        .fill(Color.clear)
                                        .frame(width: 36, height: 36)
                                        .contentShape(Circle())
                                        .position(pt)
                                        .onTapGesture {
                                            Haptic.selection()
                                            withAnimation(.spring(response: 0.25)) {
                                                selectedPointIndex = isSelected ? nil : i
                                            }
                                        }
                                }

                                // Tooltip for selected data point
                                if let idx = selectedPointIndex, idx < data.count, idx < points.count {
                                    let dp = data[idx]
                                    let pt = points[idx]
                                    inspectionTooltip(age: dp.age, rawValue: dp.value, date: dp.date, chartWidth: w, chartHeight: h, anchorPoint: pt)
                                }
                            }
                        }
                    }
                }

                // X-axis: age in months
                HStack(alignment: .top, spacing: 0) {
                    Color.clear.frame(width: yAxisWidth, height: 1)
                    GeometryReader { geo in
                        let w = geo.size.width
                        // Show 3–5 age labels
                        let labels = ageLabels(xMin: xMin, xMax: xMax)
                        ForEach(Array(labels.enumerated()), id: \.offset) { _, age in
                            let x = w * CGFloat((age - xMin) / xRange)
                            Text(baby != nil ? "\(Int(age))m" : shortDate(data[min(max(0, Int(age)), data.count - 1)].date))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.blTextTertiary)
                                .position(x: x, y: 8)
                        }
                    }
                }
                .frame(height: xAxisHeight)
            }
            .padding(.top, 10)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        )
    }

    // MARK: - Inspection Tooltip

    /// Rich tooltip shown when a data point is tapped
    private func inspectionTooltip(age: Double, rawValue: Double, date: Date, chartWidth: CGFloat, chartHeight: CGFloat, anchorPoint: CGPoint) -> some View {
        let dispValue = displayValue(rawValue)
        let valueText = "\(formatValue(dispValue)) \(unitLabel)"
        let dateText = BLDateFormatters.monthDay.string(from: date)
        let ageText = String(format: NSLocalizedString("growth.tooltip.age %@", comment: ""), Self.formatAgeMonths(age))

        // Calculate WHO percentile for this specific data point
        var pctlText: String? = nil
        if let table = whoTable {
            if let pctl = table.percentile(atMonth: age, value: rawValue) {
                pctlText = String(localized: "growth.percentile \(Int(pctl.rounded()))")
            }
        }

        // Position tooltip above the point, flipping if too close to top
        let tooltipWidth: CGFloat = 140
        let showBelow = anchorPoint.y < 60
        let tooltipY = showBelow ? anchorPoint.y + 40 : anchorPoint.y - 48
        // Clamp X so tooltip doesn't overflow chart edges
        let clampedX = min(max(tooltipWidth / 2 + 4, anchorPoint.x), chartWidth - tooltipWidth / 2 - 4)

        return VStack(spacing: 3) {
            Text(valueText)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.blGrowth)

            Text(dateText)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.blTextSecondary)

            Text(ageText)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.blTextTertiary)

            if let pctlText {
                Text(pctlText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.blTeal)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        )
        .frame(width: tooltipWidth)
        .position(x: clampedX, y: tooltipY)
        .transition(.opacity.combined(with: .scale(scale: 0.85)))
        .allowsHitTesting(false)
    }

    /// Format age in months to a human-readable string (e.g. "3.5m" or "1y 2m")
    private static func formatAgeMonths(_ months: Double) -> String {
        let totalMonths = Int(months.rounded())
        if totalMonths < 12 {
            if months < 1 {
                let weeks = Int((months * 4.345).rounded())
                return String(format: NSLocalizedString("growth.tooltip.weeks %lld", comment: ""), max(1, weeks))
            }
            return String(format: NSLocalizedString("growth.tooltip.months %lld", comment: ""), totalMonths)
        } else {
            let years = totalMonths / 12
            let remaining = totalMonths % 12
            if remaining == 0 {
                return String(format: NSLocalizedString("growth.tooltip.years %lld", comment: ""), years)
            }
            return String(format: NSLocalizedString("growth.tooltip.yearsMonths %lld %lld", comment: ""), years, remaining)
        }
    }

    // MARK: - WHO Curve Helpers

    /// Draw a filled band between two percentile curves
    private func whoFillBand(table: WHOGrowthTable, lower: WHOPercentile, upper: WHOPercentile,
                             color: Color,
                             w: CGFloat, h: CGFloat, chartMin: Double, chartRange: Double,
                             xMin: Double, xRange: Double) -> some View {
        let steps = 25
        let ageFloor = max(0, xMin)
        let ageCeil = min(Double(table.maxMonth), xMin + xRange)
        let stepSize = (ageCeil - ageFloor) / Double(steps)

        return Path { p in
            // Forward along upper
            var firstPoint = true
            for i in 0...steps {
                let age = ageFloor + Double(i) * stepSize
                if let val = table.value(atMonth: age, percentile: upper) {
                    let x = w * CGFloat((age - xMin) / xRange)
                    let y = h - h * CGFloat((val - chartMin) / chartRange)
                    if firstPoint { p.move(to: CGPoint(x: x, y: y)); firstPoint = false }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            // Backward along lower
            for i in (0...steps).reversed() {
                let age = ageFloor + Double(i) * stepSize
                if let val = table.value(atMonth: age, percentile: lower) {
                    let x = w * CGFloat((age - xMin) / xRange)
                    let y = h - h * CGFloat((val - chartMin) / chartRange)
                    p.addLine(to: CGPoint(x: x, y: y))
                }
            }
            p.closeSubpath()
        }
        .fill(color)
    }

    /// Draw a single percentile curve line
    private func whoLine(table: WHOGrowthTable, percentile: WHOPercentile,
                         w: CGFloat, h: CGFloat, chartMin: Double, chartRange: Double,
                         xMin: Double, xRange: Double) -> some View {
        let steps = 25
        let ageFloor = max(0, xMin)
        let ageCeil = min(Double(table.maxMonth), xMin + xRange)
        let stepSize = (ageCeil - ageFloor) / Double(steps)
        let isMedian = percentile == .p50

        return Path { p in
            var firstPoint = true
            for i in 0...steps {
                let age = ageFloor + Double(i) * stepSize
                if let val = table.value(atMonth: age, percentile: percentile) {
                    let x = w * CGFloat((age - xMin) / xRange)
                    let y = h - h * CGFloat((val - chartMin) / chartRange)
                    if firstPoint { p.move(to: CGPoint(x: x, y: y)); firstPoint = false }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
        }
        .stroke(
            Color.blTeal.opacity(isMedian ? 0.6 : 0.3),
            style: StrokeStyle(
                lineWidth: isMedian ? 1.5 : 0.8,
                dash: isMedian ? [] : [4, 3]
            )
        )
    }

    // MARK: - Axis Helpers

    private func ageLabels(xMin: Double, xMax: Double) -> [Double] {
        let range = xMax - xMin
        let step: Double
        if range <= 3 { step = 1 }
        else if range <= 8 { step = 2 }
        else if range <= 16 { step = 3 }
        else { step = 6 }

        let first = ceil(xMin / step) * step
        var labels: [Double] = []
        var v = first
        while v <= xMax {
            labels.append(v)
            v += step
        }
        if labels.isEmpty { labels = [xMin, xMax] }
        return labels
    }

    private func shortDate(_ date: Date) -> String {
        BLDateFormatters.monthDayCompact.string(from: date)
    }
}
