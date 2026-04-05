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

    // MARK: - Chart Area
    private var chartArea: some View {
        VStack(spacing: 16) {
            // Latest measurement
            if let latest = records.last {
                HStack(spacing: 20) {
                    latestValue(for: latest)
                }
                .padding(20)
                .blCard()
            }

            // Simple bar chart
            if records.count > 1 {
                SimpleLineChart(records: Array(records), metric: selectedMetric, unit: appState.measurementUnit)
                    .frame(height: 180)
                    .blCard()
            }
        }
    }

    private func latestValue(for r: CDGrowthRecord) -> some View {
        let unit = appState.measurementUnit
        return Group {
            if selectedMetric == .weight {
                VStack(spacing: 4) {
                    Text(String(format: "%.2f", unit.weightFromKG(r.weightKG)))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.blGrowth)
                    Text(unit.weightLabel)
                        .font(.system(size: 14))
                        .foregroundColor(.blTextSecondary)
                }
            } else if selectedMetric == .height {
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", unit.lengthFromCM(r.heightCM)))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.blGrowth)
                    Text(unit.heightLabel)
                        .font(.system(size: 14))
                        .foregroundColor(.blTextSecondary)
                }
            } else {
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", unit.lengthFromCM(r.headCircumferenceCM)))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.blGrowth)
                    Text("Head " + unit.heightLabel)
                        .font(.system(size: 14))
                        .foregroundColor(.blTextSecondary)
                }
            }
        }
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

    private func values() -> [Double] {
        records.map { r in
            switch metric {
            case .weight: return unit.weightFromKG(r.weightKG)
            case .height: return unit.lengthFromCM(r.heightCM)
            case .head:   return unit.lengthFromCM(r.headCircumferenceCM)
            }
        }.filter { $0 > 0 }
    }

    var body: some View {
        let vals = values()
        guard vals.count > 1,
              let minV = vals.min(), let maxV = vals.max(), maxV > minV else {
            return AnyView(
                Text("Not enough data")
                    .font(.system(size: 14))
                    .foregroundColor(.blTextTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }
        return AnyView(
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let range = maxV - minV
                let points = vals.enumerated().map { i, v in
                    CGPoint(
                        x: w * CGFloat(i) / CGFloat(vals.count - 1),
                        y: h - h * CGFloat((v - minV) / range)
                    )
                }
                ZStack {
                    // Fill
                    Path { p in
                        p.move(to: CGPoint(x: points[0].x, y: h))
                        points.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: points.last!.x, y: h))
                        p.closeSubpath()
                    }
                    .fill(Color.blGrowth.opacity(0.12))

                    // Line
                    Path { p in
                        p.move(to: points[0])
                        points.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(Color.blGrowth, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    // Dots
                    ForEach(0..<points.count, id: \.self) { i in
                        Circle()
                            .fill(Color.blGrowth)
                            .frame(width: 8, height: 8)
                            .position(points[i])
                    }
                }
                .padding(16)
            }
        )
    }
}
