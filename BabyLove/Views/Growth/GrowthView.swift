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

    // MARK: - Chart Area
    private var chartArea: some View {
        VStack(spacing: 16) {
            // Latest measurements overview — shows most recent non-zero value for each metric
            if !records.isEmpty {
                latestMeasurementsCard
            }

            // Simple bar chart
            if records.count > 1 {
                SimpleLineChart(records: Array(records), metric: selectedMetric, unit: appState.measurementUnit)
                    .frame(height: 220)
                    .blCard()
            }
        }
    }

    private var latestMeasurementsCard: some View {
        let unit = appState.measurementUnit
        let latestWeight = latestRecord(for: .weight)
        let latestHeight = latestRecord(for: .height)
        let latestHead   = latestRecord(for: .head)

        return HStack(spacing: 0) {
            // Weight
            metricColumn(
                value: latestWeight.map { String(format: "%.2f", unit.weightFromKG($0.weightKG)) },
                label: unit.weightLabel,
                icon: "scalemass.fill",
                isSelected: selectedMetric == .weight
            ) { selectedMetric = .weight }

            dividerLine

            // Height
            metricColumn(
                value: latestHeight.map { String(format: "%.1f", unit.lengthFromCM($0.heightCM)) },
                label: unit.heightLabel,
                icon: "ruler.fill",
                isSelected: selectedMetric == .height
            ) { selectedMetric = .height }

            dividerLine

            // Head
            metricColumn(
                value: latestHead.map { String(format: "%.1f", unit.lengthFromCM($0.headCircumferenceCM)) },
                label: "Head",
                icon: "circle.dashed",
                isSelected: selectedMetric == .head
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

    private func metricColumn(value: String?, label: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
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
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
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

// MARK: - Simple Line Chart
struct SimpleLineChart: View {
    let records: [CDGrowthRecord]
    let metric: GrowthView.GrowthMetric
    var unit: MeasurementUnit = .metric

    /// Left margin reserved for Y-axis labels
    private let yAxisWidth: CGFloat = 40
    /// Bottom margin reserved for X-axis date labels
    private let xAxisHeight: CGFloat = 24

    /// Pairs of (date, value) filtered to non-zero values
    private func dataPoints() -> [(date: Date, value: Double)] {
        records.compactMap { r -> (Date, Double)? in
            let v: Double
            switch metric {
            case .weight: v = unit.weightFromKG(r.weightKG)
            case .height: v = unit.lengthFromCM(r.heightCM)
            case .head:   v = unit.lengthFromCM(r.headCircumferenceCM)
            }
            guard v > 0, let d = r.date else { return nil }
            return (d, v)
        }
    }

    private var unitLabel: String {
        switch metric {
        case .weight: return unit.weightLabel
        case .height, .head: return unit.heightLabel
        }
    }

    /// Format value for display — weight uses 2 decimals, others 1
    private func formatValue(_ v: Double) -> String {
        metric == .weight ? String(format: "%.2f", v) : String(format: "%.1f", v)
    }

    var body: some View {
        let data = dataPoints()
        guard data.count > 1,
              let minV = data.map(\.value).min(),
              let maxV = data.map(\.value).max(),
              maxV > minV else {
            return AnyView(
                Text("Not enough data")
                    .font(.system(size: 14))
                    .foregroundColor(.blTextTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }

        // Add 10% vertical padding so dots aren't at edges
        let padding = (maxV - minV) * 0.1
        let chartMin = minV - padding
        let chartMax = maxV + padding
        let chartRange = chartMax - chartMin

        // Y-axis: 3 nice tick values
        let yTicks = [minV, (minV + maxV) / 2, maxV]

        return AnyView(
            VStack(spacing: 0) {
                // Unit label above chart
                HStack {
                    Text(unitLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.blTextTertiary)
                    Spacer()
                }
                .padding(.leading, 4)
                .padding(.bottom, 2)

                HStack(alignment: .top, spacing: 0) {
                    // Y-axis labels
                    GeometryReader { geo in
                        let h = geo.size.height
                        ForEach(yTicks, id: \.self) { tick in
                            let yFrac = CGFloat((tick - chartMin) / chartRange)
                            let y = h - h * yFrac
                            Text(formatValue(tick))
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
                        let points = data.enumerated().map { i, dp in
                            CGPoint(
                                x: w * CGFloat(i) / CGFloat(data.count - 1),
                                y: h - h * CGFloat((dp.value - chartMin) / chartRange)
                            )
                        }

                        if let first = points.first, let last = points.last {
                            ZStack {
                                // Horizontal grid lines
                                ForEach(yTicks, id: \.self) { tick in
                                    let yFrac = CGFloat((tick - chartMin) / chartRange)
                                    let y = h - h * yFrac
                                    Path { p in
                                        p.move(to: CGPoint(x: 0, y: y))
                                        p.addLine(to: CGPoint(x: w, y: y))
                                    }
                                    .stroke(Color.blTextTertiary.opacity(0.15), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
                                }

                                // Gradient fill
                                Path { p in
                                    p.move(to: CGPoint(x: first.x, y: h))
                                    points.forEach { p.addLine(to: $0) }
                                    p.addLine(to: CGPoint(x: last.x, y: h))
                                    p.closeSubpath()
                                }
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blGrowth.opacity(0.2), Color.blGrowth.opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                                // Line
                                Path { p in
                                    p.move(to: first)
                                    points.dropFirst().forEach { p.addLine(to: $0) }
                                }
                                .stroke(Color.blGrowth, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                                // Dots + value labels
                                ForEach(0..<points.count, id: \.self) { i in
                                    let pt = points[i]
                                    // Value label above dot
                                    Text(formatValue(data[i].value))
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.blGrowth)
                                        .position(x: pt.x, y: pt.y - 12)

                                    // Dot with white border
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 10, height: 10)
                                        .position(pt)
                                    Circle()
                                        .fill(Color.blGrowth)
                                        .frame(width: 7, height: 7)
                                        .position(pt)
                                }
                            }
                        }
                    }
                }

                // X-axis date labels
                HStack(alignment: .top, spacing: 0) {
                    // Spacer matching Y-axis width
                    Color.clear.frame(width: yAxisWidth, height: 1)

                    // Date labels for first, middle, last
                    GeometryReader { geo in
                        let indices = xAxisIndices(count: data.count)
                        ForEach(indices, id: \.self) { i in
                            let x = geo.size.width * CGFloat(i) / CGFloat(max(1, data.count - 1))
                            let alignment: Alignment = i == 0 ? .leading : (i == data.count - 1 ? .trailing : .center)
                            Text(shortDate(data[i].date))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.blTextTertiary)
                                .frame(width: 50, alignment: alignment)
                                .position(x: x, y: 8)
                        }
                    }
                }
                .frame(height: xAxisHeight)
            }
            .padding(.top, 12)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        )
    }

    /// Pick indices for X-axis labels: first, middle (if >2), last
    private func xAxisIndices(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        if count <= 2 { return Array(0..<count) }
        return [0, count / 2, count - 1]
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
    }
}
