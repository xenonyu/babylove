import SwiftUI
import CoreData

// MARK: - Summary View (Monthly & Yearly)

struct SummaryView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var displayedMonth: Date  // 1st of the month being viewed
    @State private var showYearlyView = false

    private let calendar = Calendar.current

    init(initialMonth: Date = Date()) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: initialMonth)
        _displayedMonth = State(initialValue: cal.date(from: comps) ?? initialMonth)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        monthSelector
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        if showYearlyView {
                            yearlyContent
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        } else {
                            monthlyContent
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle(NSLocalizedString("summary.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blPrimary)
                }
            }
        }
    }

    // MARK: - Month Selector

    private var monthSelector: some View {
        HStack {
            Button {
                Haptic.selection()
                withAnimation(.easeInOut(duration: 0.25)) {
                    showYearlyView = false
                    displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blPrimary)
                    .frame(width: 36, height: 36)
            }

            Spacer()

            Button {
                Haptic.medium()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showYearlyView.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(monthYearText)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.blTextPrimary)
                        .contentTransition(.numericText())
                    Image(systemName: showYearlyView ? "chart.bar.fill" : "calendar")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.blPrimary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(NSLocalizedString("summary.a11y.tapForYearly", comment: ""))

            Spacer()

            Button {
                Haptic.selection()
                withAnimation(.easeInOut(duration: 0.25)) {
                    showYearlyView = false
                    displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(canGoForward ? .blPrimary : .blTextTertiary)
                    .frame(width: 36, height: 36)
            }
            .disabled(!canGoForward)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(Color.blCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    private var canGoForward: Bool {
        let currentMonthStart = calendar.dateComponents([.year, .month], from: Date())
        let displayComps = calendar.dateComponents([.year, .month], from: displayedMonth)
        if let currentDate = calendar.date(from: currentMonthStart),
           let displayDate = calendar.date(from: displayComps) {
            return displayDate < currentDate
        }
        return false
    }

    private var monthYearText: String {
        if showYearlyView {
            let year = calendar.component(.year, from: displayedMonth)
            return String(year)
        }
        return BLDateFormatters.yearMonth.string(from: displayedMonth)
    }

    // MARK: - Monthly Content

    @ViewBuilder
    private var monthlyContent: some View {
        let stats = monthlyStats(for: displayedMonth)
        let prevStats = monthlyStats(for: calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth)
        let hasAnyData = stats.feedingCount > 0 || stats.sleepMinutes > 0 || stats.diaperCount > 0 || stats.hasGrowth

        if hasAnyData {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                // Feeding Card
                summaryCard(
                    icon: "drop.fill",
                    title: NSLocalizedString("summary.feeding", comment: ""),
                    color: .blFeeding,
                    stats: [
                        (NSLocalizedString("summary.totalCount", comment: ""), "\(stats.feedingCount)"),
                        (NSLocalizedString("summary.dailyAvg", comment: ""), String(format: "%.1f", stats.feedingDailyAvg)),
                        (NSLocalizedString("summary.totalVolume", comment: ""), stats.feedingVolume > 0 ? "\(Int(stats.feedingVolume)) ml" : "—"),
                    ],
                    change: stats.feedingCount - prevStats.feedingCount,
                    changeLabel: NSLocalizedString("summary.vsLastMonth", comment: "")
                )

                // Sleep Card
                summaryCard(
                    icon: "moon.fill",
                    title: NSLocalizedString("summary.sleep", comment: ""),
                    color: .blSleep,
                    stats: [
                        (NSLocalizedString("summary.totalDuration", comment: ""), formatDaysHours(minutes: stats.sleepMinutes)),
                        (NSLocalizedString("summary.dailyAvg", comment: ""), formatHoursMinutes(minutes: Int(stats.sleepDailyAvgMinutes))),
                        (NSLocalizedString("summary.longestSleep", comment: ""), formatHoursMinutes(minutes: stats.longestSleepMinutes)),
                    ],
                    change: stats.sleepMinutes - prevStats.sleepMinutes,
                    changeLabel: NSLocalizedString("summary.vsLastMonth", comment: ""),
                    changeFormatter: { diff in
                        let sign = diff > 0 ? "+" : ""
                        return "\(sign)\(formatHoursMinutes(minutes: abs(diff)))"
                    }
                )

                // Diaper Card
                summaryCard(
                    icon: "humidity.fill",
                    title: NSLocalizedString("summary.diaper", comment: ""),
                    color: .blDiaper,
                    stats: [
                        (NSLocalizedString("summary.totalCount", comment: ""), "\(stats.diaperCount)"),
                        (NSLocalizedString("summary.wet", comment: ""), "\(stats.diaperWet)"),
                        (NSLocalizedString("summary.dirty", comment: ""), "\(stats.diaperDirty)"),
                    ],
                    change: stats.diaperCount - prevStats.diaperCount,
                    changeLabel: NSLocalizedString("summary.vsLastMonth", comment: "")
                )

                // Growth Card
                growthCard(stats: stats)
            }
            .padding(.horizontal, 20)
        } else {
            emptyStateView
                .padding(.horizontal, 20)
                .padding(.top, 40)
        }
    }

    // MARK: - Summary Card

    private func summaryCard(
        icon: String,
        title: String,
        color: Color,
        stats: [(String, String)],
        change: Int,
        changeLabel: String,
        changeFormatter: ((Int) -> String)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)

                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blTextPrimary)

                Spacer()

                changeBadge(value: change, formatter: changeFormatter)
            }

            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                HStack {
                    Text(stat.0)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blTextSecondary)
                    Spacer()
                    Text(stat.1)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.blTextPrimary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.blCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(color.opacity(0.06))
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
    }

    // Growth card (special: shows delta values)
    private func growthCard(stats: MonthlyStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blGrowth)

                Text(NSLocalizedString("summary.growth", comment: ""))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blTextPrimary)

                Spacer()
            }

            if stats.hasGrowth {
                if stats.weightDelta != 0 {
                    growthRow(
                        label: NSLocalizedString("summary.weight", comment: ""),
                        value: String(format: "%+.2f kg", stats.weightDelta)
                    )
                }
                if stats.heightDelta != 0 {
                    growthRow(
                        label: NSLocalizedString("summary.height", comment: ""),
                        value: String(format: "%+.1f cm", stats.heightDelta)
                    )
                }
                if stats.headDelta != 0 {
                    growthRow(
                        label: NSLocalizedString("summary.head", comment: ""),
                        value: String(format: "%+.1f cm", stats.headDelta)
                    )
                }
                if stats.weightDelta == 0 && stats.heightDelta == 0 && stats.headDelta == 0 {
                    Text(NSLocalizedString("summary.noGrowthChange", comment: ""))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blTextTertiary)
                }
            } else {
                Text(NSLocalizedString("summary.noGrowthData", comment: ""))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.blTextTertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.blCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.blGrowth.opacity(0.06))
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
    }

    private func growthRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.blTextSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(value.hasPrefix("+") ? Color(hex: "#34C759") : (value.hasPrefix("-") ? Color(hex: "#FF3B30") : .blTextPrimary))
        }
    }

    // MARK: - Change Badge

    private func changeBadge(value: Int, formatter: ((Int) -> String)? = nil) -> some View {
        let resolved: (text: String, badgeColor: Color, icon: String) = {
            if value != 0 {
                let t: String
                if let formatter {
                    t = formatter(value)
                } else {
                    t = value > 0 ? "+\(value)" : "\(value)"
                }
                let c: Color = value > 0 ? Color(hex: "#34C759") : Color(hex: "#FF3B30")
                let i = value > 0 ? "arrow.up.right" : "arrow.down.right"
                return (t, c, i)
            } else {
                return (NSLocalizedString("summary.noChange", comment: ""), .blTextTertiary, "minus")
            }
        }()

        return HStack(spacing: 2) {
            Image(systemName: resolved.icon)
                .font(.system(size: 8, weight: .bold))
            Text(resolved.text)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(resolved.badgeColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(resolved.badgeColor.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.blTextTertiary)

            Text(NSLocalizedString("summary.noData", comment: ""))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.blTextSecondary)

            Text(NSLocalizedString("summary.noDataHint", comment: ""))
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.blTextTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .blCard()
    }

    // MARK: - Yearly Content

    @ViewBuilder
    private var yearlyContent: some View {
        let year = calendar.component(.year, from: displayedMonth)
        let yearlyData = yearlyStats(for: year)

        VStack(spacing: 20) {
            // Feeding bar chart
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blFeeding)
                    Text(NSLocalizedString("summary.feedingsByMonth", comment: ""))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.blTextPrimary)
                }

                miniBarChart(data: yearlyData.monthlyFeedingCounts, color: .blFeeding)
            }
            .padding(16)
            .blCard()
            .padding(.horizontal, 20)

            // Yearly totals
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                yearlyStatCard(
                    icon: "drop.fill",
                    value: "\(yearlyData.totalFeedings)",
                    label: NSLocalizedString("summary.yearTotalFeedings", comment: ""),
                    color: .blFeeding
                )
                yearlyStatCard(
                    icon: "moon.fill",
                    value: formatDaysHours(minutes: yearlyData.totalSleepMinutes),
                    label: NSLocalizedString("summary.yearTotalSleep", comment: ""),
                    color: .blSleep
                )
                yearlyStatCard(
                    icon: "humidity.fill",
                    value: "\(yearlyData.totalDiapers)",
                    label: NSLocalizedString("summary.yearTotalDiapers", comment: ""),
                    color: .blDiaper
                )
                yearlyStatCard(
                    icon: "star.fill",
                    value: "\(yearlyData.milestoneCount)",
                    label: NSLocalizedString("summary.yearMilestones", comment: ""),
                    color: .blGrowth
                )
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Mini Bar Chart (12 months)

    private func miniBarChart(data: [Int], color: Color) -> some View {
        let maxVal = max(data.max() ?? 1, 1)
        let monthLabels = calendar.shortMonthSymbols

        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<12, id: \.self) { i in
                VStack(spacing: 4) {
                    if data[i] > 0 {
                        Text("\(data[i])")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.blTextTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(data[i] > 0 ? color : color.opacity(0.15))
                        .frame(height: max(4, CGFloat(data[i]) / CGFloat(maxVal) * 80))

                    Text(String(monthLabels[i].prefix(1)))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.blTextTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 110)
    }

    // MARK: - Yearly Stat Card

    private func yearlyStatCard(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.blTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.blTextSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .blCard()
    }

    // MARK: - Data Fetching

    private struct MonthlyStats {
        var feedingCount: Int = 0
        var feedingVolume: Double = 0
        var feedingDailyAvg: Double = 0
        var sleepMinutes: Int = 0
        var sleepDailyAvgMinutes: Double = 0
        var longestSleepMinutes: Int = 0
        var diaperCount: Int = 0
        var diaperWet: Int = 0
        var diaperDirty: Int = 0
        var weightDelta: Double = 0
        var heightDelta: Double = 0
        var headDelta: Double = 0
        var hasGrowth: Bool = false
    }

    private func monthlyStats(for month: Date) -> MonthlyStats {
        let comps = calendar.dateComponents([.year, .month], from: month)
        guard let monthStart = calendar.date(from: comps),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return MonthlyStats()
        }
        let daysInMonth = calendar.dateComponents([.day], from: monthStart, to: min(monthEnd, Date())).day ?? 30
        let effectiveDays = max(daysInMonth, 1)

        var stats = MonthlyStats()

        // Feeding
        let feedReq: NSFetchRequest<CDFeedingRecord> = CDFeedingRecord.fetchRequest()
        feedReq.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", monthStart as NSDate, monthEnd as NSDate)
        if let feeds = try? ctx.fetch(feedReq) {
            stats.feedingCount = feeds.count
            stats.feedingVolume = feeds.reduce(0) { $0 + $1.amountML }
            stats.feedingDailyAvg = Double(feeds.count) / Double(effectiveDays)
        }

        // Sleep
        let sleepReq: NSFetchRequest<CDSleepRecord> = CDSleepRecord.fetchRequest()
        sleepReq.predicate = NSPredicate(format: "startTime >= %@ AND startTime < %@", monthStart as NSDate, monthEnd as NSDate)
        if let sleeps = try? ctx.fetch(sleepReq) {
            var totalMinutes = 0
            var longestMinutes = 0
            for s in sleeps {
                guard let start = s.startTime, let end = s.endTime else { continue }
                let mins = Int(end.timeIntervalSince(start) / 60)
                totalMinutes += mins
                longestMinutes = max(longestMinutes, mins)
            }
            stats.sleepMinutes = totalMinutes
            stats.sleepDailyAvgMinutes = Double(totalMinutes) / Double(effectiveDays)
            stats.longestSleepMinutes = longestMinutes
        }

        // Diaper
        let diaperReq: NSFetchRequest<CDDiaperRecord> = CDDiaperRecord.fetchRequest()
        diaperReq.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", monthStart as NSDate, monthEnd as NSDate)
        if let diapers = try? ctx.fetch(diaperReq) {
            stats.diaperCount = diapers.count
            for d in diapers {
                let type = d.diaperType ?? ""
                if type == "wet" { stats.diaperWet += 1 }
                else if type == "dirty" { stats.diaperDirty += 1 }
                else if type == "both" { stats.diaperWet += 1; stats.diaperDirty += 1 }
            }
        }

        // Growth — delta between first and last record in the month
        let growthReq: NSFetchRequest<CDGrowthRecord> = CDGrowthRecord.fetchRequest()
        growthReq.predicate = NSPredicate(format: "date >= %@ AND date < %@", monthStart as NSDate, monthEnd as NSDate)
        growthReq.sortDescriptors = [NSSortDescriptor(keyPath: \CDGrowthRecord.date, ascending: true)]
        if let growths = try? ctx.fetch(growthReq), growths.count >= 2,
           let first = growths.first, let last = growths.last {
            stats.hasGrowth = true
            stats.weightDelta = last.weightKG - first.weightKG
            stats.heightDelta = last.heightCM - first.heightCM
            stats.headDelta = last.headCircumferenceCM - first.headCircumferenceCM
        } else if let growths = try? ctx.fetch(growthReq), !growths.isEmpty {
            stats.hasGrowth = true
            // Single record: show as-is with no delta
        }

        return stats
    }

    private struct YearlyStats {
        var monthlyFeedingCounts: [Int] = Array(repeating: 0, count: 12)
        var totalFeedings: Int = 0
        var totalSleepMinutes: Int = 0
        var totalDiapers: Int = 0
        var milestoneCount: Int = 0
    }

    private func yearlyStats(for year: Int) -> YearlyStats {
        var comps = DateComponents()
        comps.year = year
        comps.month = 1
        comps.day = 1
        guard let yearStart = calendar.date(from: comps) else { return YearlyStats() }
        var endComps = DateComponents()
        endComps.year = year + 1
        endComps.month = 1
        endComps.day = 1
        guard let yearEnd = calendar.date(from: endComps) else { return YearlyStats() }

        var stats = YearlyStats()

        // Feeding by month
        let feedReq: NSFetchRequest<CDFeedingRecord> = CDFeedingRecord.fetchRequest()
        feedReq.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", yearStart as NSDate, yearEnd as NSDate)
        if let feeds = try? ctx.fetch(feedReq) {
            stats.totalFeedings = feeds.count
            for f in feeds {
                guard let ts = f.timestamp else { continue }
                let m = calendar.component(.month, from: ts) - 1
                if m >= 0 && m < 12 { stats.monthlyFeedingCounts[m] += 1 }
            }
        }

        // Sleep total
        let sleepReq: NSFetchRequest<CDSleepRecord> = CDSleepRecord.fetchRequest()
        sleepReq.predicate = NSPredicate(format: "startTime >= %@ AND startTime < %@", yearStart as NSDate, yearEnd as NSDate)
        if let sleeps = try? ctx.fetch(sleepReq) {
            for s in sleeps {
                guard let start = s.startTime, let end = s.endTime else { continue }
                stats.totalSleepMinutes += Int(end.timeIntervalSince(start) / 60)
            }
        }

        // Diaper total
        let diaperReq: NSFetchRequest<CDDiaperRecord> = CDDiaperRecord.fetchRequest()
        diaperReq.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", yearStart as NSDate, yearEnd as NSDate)
        stats.totalDiapers = (try? ctx.count(for: diaperReq)) ?? 0

        // Milestones
        let mileReq: NSFetchRequest<CDMilestone> = CDMilestone.fetchRequest()
        mileReq.predicate = NSPredicate(format: "date >= %@ AND date < %@", yearStart as NSDate, yearEnd as NSDate)
        stats.milestoneCount = (try? ctx.count(for: mileReq)) ?? 0

        return stats
    }

    // MARK: - Formatters

    private func formatDaysHours(minutes: Int) -> String {
        let hours = minutes / 60
        let days = hours / 24
        let remainingHours = hours % 24
        if days > 0 {
            return String(format: NSLocalizedString("summary.daysHours %lld %lld", comment: ""), days, remainingHours)
        }
        return String(format: NSLocalizedString("summary.hours %lld", comment: ""), hours)
    }

    private func formatHoursMinutes(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 {
            return String(format: NSLocalizedString("summary.hm %lld %lld", comment: ""), h, m)
        } else if h > 0 {
            return String(format: NSLocalizedString("summary.hours %lld", comment: ""), h)
        }
        return String(format: NSLocalizedString("summary.min %lld", comment: ""), m)
    }
}
