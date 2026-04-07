import SwiftUI
import CoreData

// MARK: - Prediction Engine

/// Pure-Swift prediction engine that computes next feeding time and sleep window
/// from recent CoreData records. No external dependencies.
enum PredictionEngine {

    struct FeedingPrediction {
        let predictedTime: Date
        let recordCount: Int
    }

    struct SleepPrediction {
        /// The center of the predicted sleep window (as today's date with the predicted hour/minute)
        let windowCenter: Date
        /// 30 minutes before center
        let windowStart: Date
        /// 30 minutes after center
        let windowEnd: Date
        let recordCount: Int
    }

    /// Predict next feeding time based on median interval of recent records.
    /// Returns nil if fewer than 3 records exist.
    static func predictNextFeeding(context: NSManagedObjectContext) -> FeedingPrediction? {
        let request: NSFetchRequest<CDFeedingRecord> = CDFeedingRecord.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDFeedingRecord.timestamp, ascending: false)]
        request.fetchLimit = 14

        guard let records = try? context.fetch(request),
              records.count >= 3 else { return nil }

        // Compute intervals between consecutive feedings (reverse to chronological order)
        let sorted = records.reversed().compactMap(\.timestamp)
        guard sorted.count >= 2 else { return nil }

        var intervals: [TimeInterval] = []
        for i in 1..<sorted.count {
            let interval = sorted[i].timeIntervalSince(sorted[i - 1])
            if interval > 0 { intervals.append(interval) }
        }

        guard intervals.count >= 2 else { return nil }

        // Remove top/bottom 10% as outliers before computing median
        let trimmed = trimOutliers(intervals)
        let median = computeMedian(trimmed)

        guard let lastFeeding = records.first?.timestamp else { return nil }
        let predicted = lastFeeding.addingTimeInterval(median)

        return FeedingPrediction(predictedTime: predicted, recordCount: records.count)
    }

    /// Predict golden sleep window based on circular mean of start-of-sleep time-of-day.
    /// Uses circular averaging to correctly handle times near midnight.
    /// Returns nil if fewer than 3 records exist.
    static func predictSleepWindow(context: NSManagedObjectContext) -> SleepPrediction? {
        let request: NSFetchRequest<CDSleepRecord> = CDSleepRecord.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDSleepRecord.startTime, ascending: false)]
        request.fetchLimit = 14

        guard let records = try? context.fetch(request),
              records.count >= 3 else { return nil }

        let cal = Calendar.current
        // Convert each startTime to "minutes since midnight"
        let minutesOfDay: [Int] = records.compactMap { record in
            guard let start = record.startTime else { return nil }
            let comps = cal.dateComponents([.hour, .minute], from: start)
            guard let h = comps.hour, let m = comps.minute else { return nil }
            return h * 60 + m
        }

        guard minutesOfDay.count >= 3 else { return nil }

        // Circular mean handles midnight wraparound correctly
        let avgMinutes = circularMean(minutesOfDay)
        let avgHour = avgMinutes / 60
        let avgMinute = avgMinutes % 60

        // Build today's date at that time
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = avgHour
        comps.minute = avgMinute
        comps.second = 0

        guard let center = cal.date(from: comps) else { return nil }

        // If the predicted window has already fully passed today, project to tomorrow
        let windowEnd = center.addingTimeInterval(30 * 60)
        let finalCenter: Date
        if windowEnd < now {
            finalCenter = center.addingTimeInterval(24 * 60 * 60)
        } else {
            finalCenter = center
        }

        return SleepPrediction(
            windowCenter: finalCenter,
            windowStart: finalCenter.addingTimeInterval(-30 * 60),
            windowEnd: finalCenter.addingTimeInterval(30 * 60),
            recordCount: records.count
        )
    }

    // MARK: - Statistics Helpers

    /// Circular mean for time-of-day minutes, correctly handling midnight wrap.
    /// E.g. 23:30 (1410 min) and 00:30 (30 min) averages to midnight, not noon.
    private static func circularMean(_ minutes: [Int]) -> Int {
        let totalMinutes = 24 * 60
        var sinSum = 0.0
        var cosSum = 0.0
        for m in minutes {
            let angle = Double(m) / Double(totalMinutes) * 2.0 * .pi
            sinSum += sin(angle)
            cosSum += cos(angle)
        }
        let avgAngle = atan2(sinSum / Double(minutes.count), cosSum / Double(minutes.count))
        var result = Int(avgAngle / (2.0 * .pi) * Double(totalMinutes))
        if result < 0 { result += totalMinutes }
        return result
    }

    private static func trimOutliers(_ values: [TimeInterval]) -> [TimeInterval] {
        guard values.count >= 5 else { return values }
        let sorted = values.sorted()
        let trimCount = max(1, sorted.count / 10)
        return Array(sorted.dropFirst(trimCount).dropLast(trimCount))
    }

    private static func computeMedian(_ values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        } else {
            return sorted[mid]
        }
    }
}

// MARK: - Confidence Level

private enum ConfidenceLevel: Int {
    case low = 1      // < 5 records
    case medium = 2   // 5–10 records
    case high = 3     // > 10 records

    init(recordCount: Int) {
        if recordCount > 10 { self = .high }
        else if recordCount >= 5 { self = .medium }
        else { self = .low }
    }
}

// MARK: - Smart Prediction Card View

struct SmartPredictionCard: View {
    @Environment(\.managedObjectContext) private var ctx

    /// Callbacks for tap navigation
    var onTapFeeding: () -> Void = {}
    var onTapSleep: () -> Void = {}

    @State private var feedingPrediction: PredictionEngine.FeedingPrediction?
    @State private var sleepPrediction: PredictionEngine.SleepPrediction?
    @State private var hasEnoughFeeding = false
    @State private var hasEnoughSleep = false
    /// Timer tick to keep countdowns live
    @State private var tick: Int = 0
    @State private var countdownTimer: Timer?

    var body: some View {
        Group {
            if hasEnoughFeeding || hasEnoughSleep {
                predictionContent
            } else {
                insufficientDataCard
            }
        }
        .padding(.horizontal, 20)
        .onAppear { refreshPredictions(); startCountdown() }
        .onDisappear { stopCountdown() }
    }

    // MARK: - Sufficient Data Card

    private var predictionContent: some View {
        VStack(spacing: 14) {
            // Header row
            HStack {
                HStack(spacing: 4) {
                    Text("✦")
                        .font(.system(size: 14))
                        .foregroundColor(.blPrimary)
                    Text(NSLocalizedString("prediction.title", comment: ""))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.blTextPrimary)
                }
                Spacer()
                let count = max(feedingPrediction?.recordCount ?? 0, sleepPrediction?.recordCount ?? 0)
                Text(String(format: NSLocalizedString("prediction.basedOn %lld", comment: ""), count))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.blTextTertiary)
            }

            HStack(spacing: 12) {
                // Left: Feeding prediction
                if let fp = feedingPrediction {
                    feedingColumn(fp)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Haptic.light()
                            onTapFeeding()
                        }
                } else {
                    columnPlaceholder(
                        icon: "fork.knife",
                        color: .blFeeding,
                        title: NSLocalizedString("prediction.feeding", comment: "")
                    )
                }

                // Divider
                Rectangle()
                    .fill(Color.blTextTertiary.opacity(0.15))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 4)

                // Right: Sleep prediction
                if let sp = sleepPrediction {
                    sleepColumn(sp)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Haptic.light()
                            onTapSleep()
                        }
                } else {
                    columnPlaceholder(
                        icon: "moon.fill",
                        color: .blSleep,
                        title: NSLocalizedString("prediction.sleepWindow", comment: "")
                    )
                }
            }
        }
        .padding(16)
        .background(Color.blBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    // MARK: - Feeding Column

    private func feedingColumn(_ prediction: PredictionEngine.FeedingPrediction) -> some View {
        let confidence = ConfidenceLevel(recordCount: prediction.recordCount)
        let _ = tick // force refresh on tick

        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.blFeeding.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "fork.knife")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.blFeeding)
            }

            Text(NSLocalizedString("prediction.nextFeeding", comment: ""))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.blTextSecondary)

            Text(formatTime(prediction.predictedTime))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.blFeeding)

            Text(countdownText(to: prediction.predictedTime))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.blTextTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            confidenceDots(level: confidence, color: .blFeeding)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(NSLocalizedString("prediction.nextFeeding", comment: "")), \(formatTime(prediction.predictedTime)), \(countdownText(to: prediction.predictedTime))")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Sleep Column

    private func sleepColumn(_ prediction: PredictionEngine.SleepPrediction) -> some View {
        let confidence = ConfidenceLevel(recordCount: prediction.recordCount)
        let _ = tick

        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.blSleep.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "moon.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.blSleep)
            }

            Text(NSLocalizedString("prediction.sleepWindow", comment: ""))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.blTextSecondary)

            Text("\(formatTime(prediction.windowStart))–\(formatTime(prediction.windowEnd))")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.blSleep)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(sleepWindowRelationText(prediction))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.blTextTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            confidenceDots(level: confidence, color: .blSleep)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(NSLocalizedString("prediction.sleepWindow", comment: "")), \(formatTime(prediction.windowStart)) – \(formatTime(prediction.windowEnd)), \(sleepWindowRelationText(prediction))")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Placeholder Column (not enough data for one type)

    private func columnPlaceholder(icon: String, color: Color, title: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.08))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(color.opacity(0.4))
            }

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.blTextTertiary)

            Text("—")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(color.opacity(0.3))

            Text(NSLocalizedString("prediction.needMore", comment: ""))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.blTextTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            // Empty dots for visual alignment
            confidenceDots(level: .low, color: color.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Insufficient Data Card (both types lack data)

    private var insufficientDataCard: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 4) {
                    Text("✦")
                        .font(.system(size: 14))
                        .foregroundColor(.blPrimary.opacity(0.5))
                    Text(NSLocalizedString("prediction.title", comment: ""))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.blTextPrimary.opacity(0.5))
                }
                Spacer()
            }

            VStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 28))
                    .foregroundColor(.blTextTertiary)

                Text(NSLocalizedString("prediction.insufficientData", comment: ""))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.blTextSecondary)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("prediction.insufficientHint", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(.blTextTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.blBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundColor(.blTextTertiary.opacity(0.35))
        )
    }

    // MARK: - Confidence Dots

    private func confidenceDots(level: ConfidenceLevel, color: Color) -> some View {
        HStack(spacing: 4) {
            ForEach(1...3, id: \.self) { dot in
                Circle()
                    .fill(dot <= level.rawValue ? color : color.opacity(0.2))
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Formatting Helpers

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// Countdown or "overdue" text relative to now
    private func countdownText(to target: Date) -> String {
        let now = Date()
        let diff = target.timeIntervalSince(now)

        if diff > 0 {
            // Future
            let totalMinutes = Int(diff / 60)
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if hours > 0 {
                return String(format: NSLocalizedString("prediction.countdown.hm %lld %lld", comment: ""), hours, minutes)
            } else {
                return String(format: NSLocalizedString("prediction.countdown.m %lld", comment: ""), minutes)
            }
        } else {
            // Past
            let totalMinutes = Int(-diff / 60)
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if hours > 0 {
                return String(format: NSLocalizedString("prediction.overdue.hm %lld %lld", comment: ""), hours, minutes)
            } else if minutes > 0 {
                return String(format: NSLocalizedString("prediction.overdue.m %lld", comment: ""), minutes)
            } else {
                return NSLocalizedString("prediction.now", comment: "")
            }
        }
    }

    /// Contextual text for the sleep window relative to now
    private func sleepWindowRelationText(_ prediction: PredictionEngine.SleepPrediction) -> String {
        let now = Date()
        if now < prediction.windowStart {
            return countdownText(to: prediction.windowStart)
        } else if now <= prediction.windowEnd {
            return NSLocalizedString("prediction.sleepNow", comment: "")
        } else {
            return NSLocalizedString("prediction.sleepPassed", comment: "")
        }
    }

    // MARK: - Data Refresh

    private func refreshPredictions() {
        feedingPrediction = PredictionEngine.predictNextFeeding(context: ctx)
        sleepPrediction = PredictionEngine.predictSleepWindow(context: ctx)
        hasEnoughFeeding = feedingPrediction != nil
        hasEnoughSleep = sleepPrediction != nil
    }

    @MainActor
    private func startCountdown() {
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in
                tick += 1
                refreshPredictions()
            }
        }
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
}
