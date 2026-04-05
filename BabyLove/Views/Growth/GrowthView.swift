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

    @FetchRequest(
        entity: CDGrowthRecord.entity(),
        sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)]
    ) private var records: FetchedResults<CDGrowthRecord>

    enum GrowthMetric: String, CaseIterable {
        case weight = "Weight"
        case height = "Height"
        case head   = "Head"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        // Metric picker
                        Picker("Metric", selection: $selectedMetric) {
                            ForEach(GrowthMetric.allCases, id: \.self) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)

                        // Chart area
                        chartArea
                            .padding(.horizontal, 20)

                        // Records list
                        if !records.isEmpty {
                            VStack(spacing: 12) {
                                BLSectionHeader(title: "Records")
                                    .padding(.horizontal, 20)
                                let displayed = Array(records.suffix(10).reversed())
                                VStack(spacing: 0) {
                                    ForEach(Array(displayed.enumerated()), id: \.element.id) { index, r in
                                        growthRow(r)
                                            .contentShape(Rectangle())
                                            .onTapGesture { recordToEdit = r }
                                            .contextMenu {
                                                Button {
                                                    recordToEdit = r
                                                } label: {
                                                    Label("Edit", systemImage: "pencil")
                                                }
                                                Button(role: .destructive) {
                                                    recordToDelete = r
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                        if index < displayed.count - 1 {
                                            Divider().padding(.leading, 56)
                                        }
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
            .navigationTitle("Growth")
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
        .alert("Delete Record?", isPresented: Binding(
            get: { recordToDelete != nil },
            set: { if !$0 { recordToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { recordToDelete = nil }
            Button("Delete", role: .destructive) {
                Haptic.warning()
                if let obj = recordToDelete {
                    withAnimation { vm.deleteObject(obj, in: ctx) }
                }
                recordToDelete = nil
            }
        } message: {
            Text("This record will be permanently removed.")
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

    // MARK: - Chart Area
    private var chartArea: some View {
        VStack(spacing: 16) {
            // Latest measurements overview — shows most recent non-zero value for each metric
            if !records.isEmpty {
                latestMeasurementsCard
            }

            // Growth chart with WHO percentile curves
            if records.count > 1 {
                SimpleLineChart(
                    records: Array(records),
                    metric: selectedMetric,
                    unit: appState.measurementUnit,
                    baby: appState.currentBaby
                )
                .frame(height: 260)
                .blCard()
            }
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

        return HStack(spacing: 0) {
            // Weight
            metricColumn(
                value: latestWeight.map { String(format: "%.2f", unit.weightFromKG($0.weightKG)) },
                label: unit.weightLabel,
                icon: "scalemass.fill",
                isSelected: selectedMetric == .weight,
                percentile: weightPctl
            ) { selectedMetric = .weight }

            dividerLine

            // Height
            metricColumn(
                value: latestHeight.map { String(format: "%.1f", unit.lengthFromCM($0.heightCM)) },
                label: unit.heightLabel,
                icon: "ruler.fill",
                isSelected: selectedMetric == .height,
                percentile: heightPctl
            ) { selectedMetric = .height }

            dividerLine

            // Head
            metricColumn(
                value: latestHead.map { String(format: "%.1f", unit.lengthFromCM($0.headCircumferenceCM)) },
                label: "Head",
                icon: "circle.dashed",
                isSelected: selectedMetric == .head,
                percentile: headPctl
            ) { selectedMetric = .head }
        }
        .padding(.vertical, 16)
        .blCard()
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.blSurface)
            .frame(width: 1, height: 44)
    }

    private func metricColumn(value: String?, label: String, icon: String, isSelected: Bool, percentile: Int? = nil, action: @escaping () -> Void) -> some View {
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
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    /// Color coding for percentile badges: green for normal, amber for watch, red for concern
    private func percentileColor(_ pctl: Int) -> Color {
        if pctl < 3 || pctl > 97 { return .blPrimary }       // Outside normal — coral/alert
        if pctl < 15 || pctl > 85 { return .blGrowth }       // Worth watching — amber
        return .blTeal                                         // Healthy range — teal
    }

    private func growthRow(_ r: CDGrowthRecord) -> some View {
        let unit = appState.measurementUnit
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
                Text(r.date.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.blTextPrimary)
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
                        Text("HC \(String(format: "%.1f", unit.lengthFromCM(r.headCircumferenceCM))) \(unit.heightLabel)")
                            .font(.system(size: 13))
                            .foregroundColor(.blTextSecondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(.blGrowth.opacity(0.4))
            Text("No growth records yet")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.blTextSecondary)
            Text("Tap + to add your baby's first measurement")
                .font(.system(size: 14))
                .foregroundColor(.blTextTertiary)
                .multilineTextAlignment(.center)
            Button("Add Measurement") { showLog = true }
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
        guard data.count > 1 else {
            return AnyView(
                Text("Not enough data")
                    .font(.system(size: 14))
                    .foregroundColor(.blTextTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }

        // Determine chart bounds
        let rawValues = data.map(\.value)
        guard let ageMin = data.map(\.age).min(),
              let ageMax = data.map(\.age).max() else {
            return AnyView(
                Text("Not enough data")
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
                Text("Not enough data")
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

        // Age range for X axis
        let agePadding = max((ageMax - ageMin) * 0.05, 0.5)
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
                            Text("WHO")
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

                                // Dots + value labels
                                ForEach(0..<points.count, id: \.self) { i in
                                    let pt = points[i]
                                    Text(formatValue(displayValue(data[i].value)))
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundColor(.blGrowth)
                                        .position(x: pt.x, y: pt.y - 12)

                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 9, height: 9)
                                        .position(pt)
                                    Circle()
                                        .fill(Color.blGrowth)
                                        .frame(width: 6, height: 6)
                                        .position(pt)
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
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("Md")
        return f.string(from: date)
    }
}
