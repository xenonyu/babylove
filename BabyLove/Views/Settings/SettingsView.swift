import SwiftUI
import CoreData
import UniformTypeIdentifiers
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var ctx
    @State private var showEditBaby = false
    @State private var showResetAlert = false
    @State private var showExportShare = false
    @State private var exportFileURL: URL?
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showExportError = false

    // Feeding reminder state
    @State private var feedingReminderEnabled = NotificationManager.shared.isEnabled
    @State private var feedingReminderInterval = NotificationManager.shared.intervalMinutes
    @State private var notificationDenied = false
    /// Pre-computed message shown in the reset confirmation dialog
    @State private var resetConfirmMessage = ""

    // Journey stats
    @State private var journeyStats: JourneyStats?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()
                List {
                    // Baby profile
                    Section {
                        if let baby = appState.currentBaby {
                            Button {
                                showEditBaby = true
                            } label: {
                                HStack(spacing: 14) {
                                    BabyAvatarView(baby: baby, size: 50)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(baby.name)
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundColor(.blTextPrimary)
                                        Text(baby.localizedAge)
                                            .font(.system(size: 14))
                                            .foregroundColor(.blTextSecondary)
                                        Text(baby.birthDate.formatted(date: .long, time: .omitted))
                                            .font(.system(size: 12))
                                            .foregroundColor(.blTextTertiary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(.blTextTertiary)
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    } header: {
                        Text(String(localized: "settings.section.babyProfile"))
                    }

                    // Units
                    Section {
                        Picker(String(localized: "settings.units"), selection: Binding(
                            get: { appState.measurementUnit },
                            set: { appState.setMeasurementUnit($0) }
                        )) {
                            ForEach(MeasurementUnit.allCases, id: \.self) { u in
                                Text(u.displayName).tag(u)
                            }
                        }
                    } header: {
                        Text(String(localized: "settings.section.measurements"))
                    }

                    // Feeding reminders
                    Section {
                        Toggle(isOn: $feedingReminderEnabled) {
                            Label(String(localized: "settings.feedingReminders"), systemImage: "bell.badge.fill")
                        }
                        .tint(.blFeeding)
                        .onChange(of: feedingReminderEnabled) { _, enabled in
                            Task { @MainActor in
                                if enabled {
                                    let granted = await NotificationManager.shared.requestPermission()
                                    if granted {
                                        NotificationManager.shared.isEnabled = true
                                        // Schedule relative to last actual feeding time
                                        NotificationManager.shared.scheduleFeedingReminder(afterFeedingAt: lastFeedingTime())
                                    } else {
                                        feedingReminderEnabled = false
                                        notificationDenied = true
                                    }
                                } else {
                                    NotificationManager.shared.isEnabled = false
                                }
                            }
                        }

                        if feedingReminderEnabled {
                            Picker(selection: $feedingReminderInterval) {
                                ForEach(NotificationManager.ReminderInterval.options) { opt in
                                    Text(opt.label).tag(opt.id)
                                }
                            } label: {
                                Label(String(localized: "settings.interval"), systemImage: "clock.arrow.circlepath")
                            }
                            .onChange(of: feedingReminderInterval) { _, newVal in
                                NotificationManager.shared.intervalMinutes = newVal
                                // Re-schedule with new interval relative to last feeding
                                NotificationManager.shared.scheduleFeedingReminder(afterFeedingAt: lastFeedingTime())
                            }
                        }
                    } header: {
                        Text(String(localized: "settings.section.reminders"))
                    } footer: {
                        Text(feedingReminderEnabled
                             ? String(localized: "settings.reminders.footer.on")
                             : String(localized: "settings.reminders.footer.off"))
                    }

                    // Data export
                    Section {
                        Button {
                            exportAllData()
                        } label: {
                            HStack {
                                Label(String(localized: "settings.exportCSV"), systemImage: "square.and.arrow.up")
                                Spacer()
                                if isExporting {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        }
                        .disabled(isExporting)
                    } header: {
                        Text(String(localized: "settings.section.data"))
                    } footer: {
                        Text(String(localized: "settings.export.footer"))
                    }

                    // Your Journey — motivational stats overview
                    if let stats = journeyStats, stats.totalRecords > 0 {
                        Section {
                            // Total records
                            HStack {
                                Label(String(localized: "settings.journey.totalRecords"), systemImage: "heart.text.clipboard.fill")
                                Spacer()
                                Text("\(stats.totalRecords)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.blPrimary)
                            }
                            .accessibilityElement(children: .combine)

                            // Tracking duration
                            if let daysText = stats.trackingDurationText {
                                HStack {
                                    Label(String(localized: "settings.journey.tracking"), systemImage: "calendar.badge.clock")
                                    Spacer()
                                    Text(daysText)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.blTextSecondary)
                                }
                                .accessibilityElement(children: .combine)
                            }

                            // Logging streak
                            if stats.currentStreak > 0 {
                                HStack {
                                    Label {
                                        Text(String(localized: "settings.journey.streak"))
                                    } icon: {
                                        Image(systemName: "flame.fill")
                                            .foregroundColor(.orange)
                                    }
                                    Spacer()
                                    HStack(spacing: 6) {
                                        Text(String(format: NSLocalizedString("settings.journey.streakDays %lld", comment: ""), stats.currentStreak))
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.orange)
                                        if stats.longestStreak > stats.currentStreak {
                                            Text("·")
                                                .foregroundColor(.blTextTertiary)
                                            Text(String(format: NSLocalizedString("settings.journey.bestStreak %lld", comment: ""), stats.longestStreak))
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.blTextTertiary)
                                        }
                                    }
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(String(format: NSLocalizedString("settings.journey.streakA11y %lld %lld", comment: ""), stats.currentStreak, stats.longestStreak))
                            }

                            // Category breakdown
                            VStack(spacing: 8) {
                                journeyStatRow(icon: "drop.fill", color: .blFeeding,
                                               label: NSLocalizedString("home.feedings", comment: ""),
                                               count: stats.feedings)
                                journeyStatRow(icon: "moon.zzz.fill", color: .blSleep,
                                               label: NSLocalizedString("home.sleep", comment: ""),
                                               count: stats.sleeps)
                                journeyStatRow(icon: "oval.fill", color: .blDiaper,
                                               label: NSLocalizedString("home.diapers", comment: ""),
                                               count: stats.diapers)
                                journeyStatRow(icon: "chart.bar.fill", color: .blGrowth,
                                               label: NSLocalizedString("growth.title", comment: ""),
                                               count: stats.growths)
                                journeyStatRow(icon: "star.fill", color: .blPrimary,
                                               label: NSLocalizedString("memory.title", comment: ""),
                                               count: stats.milestones)
                            }
                            .padding(.vertical, 4)
                        } header: {
                            Text(String(localized: "settings.section.journey"))
                        } footer: {
                            if let firstDate = stats.firstRecordDate {
                                Text(String(format: NSLocalizedString("settings.journey.since %@", comment: ""),
                                            firstDate.formatted(date: .long, time: .omitted)))
                            }
                        }
                    }

                    // App info
                    Section {
                        HStack {
                            Label(String(localized: "settings.version"), systemImage: "info.circle")
                            Spacer()
                            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
                                .foregroundColor(.blTextSecondary)
                        }
                        if let privacyURL = URL(string: "https://babylove.app/privacy") {
                            Link(destination: privacyURL) {
                                Label(String(localized: "settings.privacyPolicy"), systemImage: "hand.raised.fill")
                            }
                        }
                    } header: {
                        Text(String(localized: "settings.section.about"))
                    }

                    // Danger zone
                    Section {
                        Button(role: .destructive) {
                            resetConfirmMessage = buildResetConfirmMessage()
                            showResetAlert = true
                        } label: {
                            Label(String(localized: "settings.resetAllData"), systemImage: "trash.fill")
                        }
                    } header: {
                        Text(String(localized: "settings.section.dangerZone"))
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(String(localized: "settings.title"))
            .navigationBarTitleDisplayMode(.large)
            .task {
                // Sync toggle with actual notification permission
                let status = await NotificationManager.shared.authorizationStatus()
                if status == .denied && feedingReminderEnabled {
                    feedingReminderEnabled = false
                    NotificationManager.shared.isEnabled = false
                }
                // Load journey stats
                journeyStats = JourneyStats.load(ctx: PersistenceController.shared.container.viewContext)
            }
        }
        .sheet(isPresented: $showEditBaby) {
            EditBabyView()
        }
        .sheet(isPresented: $showExportShare) {
            if let url = exportFileURL {
                ShareSheet(activityItems: [url])
            }
        }
        .alert(String(localized: "settings.reset.title"), isPresented: $showResetAlert) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "settings.reset.confirm"), role: .destructive) {
                Haptic.warning()
                resetAllData()
            }
        } message: {
            Text(resetConfirmMessage)
        }
        .alert(String(localized: "settings.notifications.disabled"), isPresented: $notificationDenied) {
            Button(String(localized: "settings.openSettings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.notifications.enableMessage"))
        }
        .alert(String(localized: "settings.export.failed"), isPresented: $showExportError) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(exportError ?? NSLocalizedString("settings.export.unknownError", comment: ""))
        }
    }

    // MARK: - Export

    private func exportAllData() {
        isExporting = true
        // Capture values for use in background task
        let unit = appState.measurementUnit
        let baby = appState.currentBaby
        let babyName = baby?.name ?? "Baby"
        let babyAge = baby?.ageText ?? ""
        let babyBirthDate = baby?.birthDate
        let exportDate = Date()

        Task.detached(priority: .userInitiated) {
            // Use a dedicated background context so we don't block the main thread
            let bgCtx = PersistenceController.shared.container.newBackgroundContext()
            bgCtx.automaticallyMergesChangesFromParent = true

            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
            // Time-only formatter for use off main thread (Date.formatted is MainActor)
            let timeFormatter = DateFormatter()
            timeFormatter.dateStyle = .none
            timeFormatter.timeStyle = .short

            // Date formatter for summary header (locale-aware, long date style)
            let longDateFormatter = DateFormatter()
            longDateFormatter.dateStyle = .long
            longDateFormatter.timeStyle = .none

            // Pre-resolve localized strings on the calling context (safe from detached task)
            let hdrRecordType = NSLocalizedString("export.header.recordType", comment: "")
            let hdrDate       = NSLocalizedString("export.header.date", comment: "")
            let hdrTime       = NSLocalizedString("export.header.time", comment: "")
            let hdrDetails    = NSLocalizedString("export.header.details", comment: "")
            let hdrNotes      = NSLocalizedString("export.header.notes", comment: "")

            // Summary header labels
            let sumTitle   = NSLocalizedString("export.summary.title", comment: "")
            let sumName    = NSLocalizedString("export.summary.name", comment: "")
            let sumAge     = NSLocalizedString("export.summary.age", comment: "")
            let sumBirth   = NSLocalizedString("export.summary.birthDate", comment: "")
            let sumExport  = NSLocalizedString("export.summary.exportDate", comment: "")
            let sumRange   = NSLocalizedString("export.summary.dateRange", comment: "")
            let sumTotal   = NSLocalizedString("export.summary.totalRecords", comment: "")
            let sumTo      = NSLocalizedString("export.summary.to", comment: "")
            let typeFeeding   = NSLocalizedString("export.type.feeding", comment: "")
            let typeSleep     = NSLocalizedString("export.type.sleep", comment: "")
            let typeDiaper    = NSLocalizedString("export.type.diaper", comment: "")
            let typeGrowth    = NSLocalizedString("export.type.growth", comment: "")
            let typeMilestone = NSLocalizedString("export.type.milestone", comment: "")
            let sleepOngoing  = NSLocalizedString("export.sleep.ongoing", comment: "")
            let feedingOngoing = NSLocalizedString("export.feeding.ongoing", comment: "")
            let mCompleted    = NSLocalizedString("export.milestone.completed", comment: "")
            let mInProgress   = NSLocalizedString("export.milestone.inProgress", comment: "")

            do {
                let csv: String = try bgCtx.performAndWait {
                    // --- Summary Header ---
                    var csv = "\(sumTitle)\n"
                    csv += "\(sumName),\(Self.csvEscape(babyName))\n"
                    if !babyAge.isEmpty {
                        csv += "\(sumAge),\(babyAge)\n"
                    }
                    if let birth = babyBirthDate {
                        csv += "\(sumBirth),\(longDateFormatter.string(from: birth))\n"
                    }
                    csv += "\(sumExport),\(longDateFormatter.string(from: exportDate))\n"

                    // Count all records to build summary totals
                    let feedReq: NSFetchRequest<CDFeedingRecord> = CDFeedingRecord.fetchRequest()
                    feedReq.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
                    let feedings = try bgCtx.fetch(feedReq)

                    let sleepReq: NSFetchRequest<CDSleepRecord> = CDSleepRecord.fetchRequest()
                    sleepReq.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: true)]
                    let sleeps = try bgCtx.fetch(sleepReq)

                    let diaperReq: NSFetchRequest<CDDiaperRecord> = CDDiaperRecord.fetchRequest()
                    diaperReq.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
                    let diapers = try bgCtx.fetch(diaperReq)

                    let growthReq: NSFetchRequest<CDGrowthRecord> = CDGrowthRecord.fetchRequest()
                    growthReq.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
                    let growths = try bgCtx.fetch(growthReq)

                    let mileReq: NSFetchRequest<CDMilestone> = CDMilestone.fetchRequest()
                    mileReq.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
                    let milestones = try bgCtx.fetch(mileReq)

                    let totalRecords = feedings.count + sleeps.count + diapers.count + growths.count + milestones.count
                    csv += "\(sumTotal),\(totalRecords) (\(typeFeeding): \(feedings.count) / \(typeSleep): \(sleeps.count) / \(typeDiaper): \(diapers.count) / \(typeGrowth): \(growths.count) / \(typeMilestone): \(milestones.count))\n"

                    // Data range (earliest → latest record date)
                    let allDates: [Date] = [
                        feedings.first?.timestamp, feedings.last?.timestamp,
                        sleeps.first?.startTime, sleeps.last?.startTime,
                        diapers.first?.timestamp, diapers.last?.timestamp,
                        growths.first?.date, growths.last?.date,
                        milestones.first?.date, milestones.last?.date
                    ].compactMap { $0 }
                    if let earliest = allDates.min(), let latest = allDates.max() {
                        csv += "\(sumRange),\(longDateFormatter.string(from: earliest)) \(sumTo) \(longDateFormatter.string(from: latest))\n"
                    }

                    // Blank row separator before data
                    csv += "\n"

                    // --- Data Header ---
                    csv += "\(hdrRecordType),\(hdrDate),\(hdrTime),\(hdrDetails),\(hdrNotes)\n"
                    for r in feedings {
                        let date = r.timestamp.map { dateFormatter.string(from: $0) } ?? ""
                        let time = r.timestamp.map { timeFormatter.string(from: $0) } ?? ""
                        let ft = FeedType(rawValue: r.feedType ?? "")
                        let feedType = ft?.displayName ?? r.feedType ?? ""
                        var details = [feedType]
                        // Detect ongoing feeding timer (breast/pump with durationMinutes == 0)
                        let isOngoing = (ft == .breast || ft == .pump) && r.durationMinutes == 0
                        if isOngoing {
                            details.append(feedingOngoing)
                        } else if r.durationMinutes > 0 {
                            details.append(DurationFormat.standard(r.durationMinutes))
                        }
                        if r.amountML > 0 {
                            let val = unit.volumeFromML(r.amountML)
                            details.append(unit == .metric ? "\(Int(val)) \(unit.volumeLabel)" : String(format: "%.1f %@", val, unit.volumeLabel))
                        }
                        if let side = r.breastSide, !side.isEmpty {
                            details.append(BreastSide(rawValue: side)?.displayName ?? side)
                        }
                        let notes = Self.csvEscape(r.notes)
                        csv += "\(typeFeeding),\(date),\(time),\(Self.csvEscape(details.joined(separator: "; "))),\(notes)\n"
                    }

                    // Sleep records
                    for r in sleeps {
                        let date = r.startTime.map { dateFormatter.string(from: $0) } ?? ""
                        let startTime = r.startTime.map { timeFormatter.string(from: $0) } ?? ""
                        var details = [String]()
                        if let loc = r.location, let sl = SleepLocation(rawValue: loc) {
                            details.append(sl.displayName)
                        }
                        if let s = r.startTime, let e = r.endTime {
                            let mins = Int(e.timeIntervalSince(s) / 60)
                            details.append(DurationFormat.fromMinutes(mins))
                            details.append(String(format: NSLocalizedString("export.sleep.end %@", comment: ""), timeFormatter.string(from: e)))
                        } else {
                            details.append(sleepOngoing)
                        }
                        let notes = Self.csvEscape(r.notes)
                        csv += "\(typeSleep),\(date),\(startTime),\(Self.csvEscape(details.joined(separator: "; "))),\(notes)\n"
                    }

                    // Diaper records
                    for r in diapers {
                        let date = r.timestamp.map { dateFormatter.string(from: $0) } ?? ""
                        let time = r.timestamp.map { timeFormatter.string(from: $0) } ?? ""
                        let dType = DiaperType(rawValue: r.diaperType ?? "")?.displayName ?? r.diaperType ?? ""
                        let notes = Self.csvEscape(r.notes)
                        csv += "\(typeDiaper),\(date),\(time),\(dType),\(notes)\n"
                    }

                    // Growth records
                    for r in growths {
                        let date = r.date.map { dateFormatter.string(from: $0) } ?? ""
                        var details = [String]()
                        if r.weightKG > 0 {
                            let w = unit.weightFromKG(r.weightKG)
                            details.append(String(format: "%.2f %@", w, unit.weightLabel))
                        }
                        if r.heightCM > 0 {
                            let h = unit.lengthFromCM(r.heightCM)
                            details.append(String(format: NSLocalizedString("export.growth.height %@ %@", comment: ""), String(format: "%.1f", h), unit.heightLabel))
                        }
                        if r.headCircumferenceCM > 0 {
                            let hc = unit.lengthFromCM(r.headCircumferenceCM)
                            details.append(String(format: NSLocalizedString("export.growth.head %@ %@", comment: ""), String(format: "%.1f", hc), unit.heightLabel))
                        }
                        let notes = Self.csvEscape(r.notes)
                        csv += "\(typeGrowth),\(date),,\(Self.csvEscape(details.joined(separator: "; "))),\(notes)\n"
                    }

                    // Milestones
                    for r in milestones {
                        let date = r.date.map { dateFormatter.string(from: $0) } ?? ""
                        let title = Self.csvEscape(r.title)
                        let cat = MilestoneCategory(rawValue: r.category ?? "")?.displayName ?? r.category ?? ""
                        let status = r.isCompleted ? mCompleted : mInProgress
                        let notes = Self.csvEscape(r.notes)
                        csv += "\(typeMilestone),\(date),,\(title) [\(cat)] (\(status)),\(notes)\n"
                    }

                    return csv
                }

                // Write to temp file with UTF-8 BOM so Excel correctly
                // detects encoding for CJK characters (中文/日本語/한국어).
                let fileDateStr = BLDateFormatters.isoDate.string(from: Date())
                let fileName = "\(babyName)_BabyLove_Export_\(fileDateStr).csv"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                let bom = Data([0xEF, 0xBB, 0xBF])
                let csvData = bom + (csv.data(using: .utf8) ?? Data())
                try csvData.write(to: tempURL)

                await MainActor.run {
                    exportFileURL = tempURL
                    isExporting = false
                    showExportShare = true
                }

            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                    showExportError = true
                }
            }
        }
    }

    /// Fetch the most recent feeding timestamp from CoreData so that
    /// reminders scheduled from Settings fire relative to the last actual
    /// feeding, not from "right now".
    private func lastFeedingTime() -> Date {
        let req: NSFetchRequest<CDFeedingRecord> = CDFeedingRecord.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        req.fetchLimit = 1
        if let last = (try? ctx.fetch(req))?.first, let ts = last.timestamp {
            return ts
        }
        return Date() // no feedings yet — fall back to now
    }

    private static func csvEscape(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func fileDate() -> String {
        BLDateFormatters.isoDate.string(from: Date())
    }

    /// Build a detailed confirmation message showing how many records will be deleted.
    /// Helps parents make an informed decision before irreversible data loss.
    private func buildResetConfirmMessage() -> String {
        let viewCtx = PersistenceController.shared.container.viewContext

        func count(entity: String) -> Int {
            let req = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            return (try? viewCtx.count(for: req)) ?? 0
        }

        let feedings   = count(entity: "CDFeedingRecord")
        let sleeps     = count(entity: "CDSleepRecord")
        let diapers    = count(entity: "CDDiaperRecord")
        let growths    = count(entity: "CDGrowthRecord")
        let milestones = count(entity: "CDMilestone")
        let total = feedings + sleeps + diapers + growths + milestones

        // If no records at all, show the generic message
        guard total > 0 else {
            return String(localized: "settings.reset.message")
        }

        // Build a list of non-zero record counts
        var parts: [String] = []
        if feedings > 0 {
            parts.append(String(format: NSLocalizedString("settings.reset.countFeedings %lld", comment: ""), feedings))
        }
        if sleeps > 0 {
            parts.append(String(format: NSLocalizedString("settings.reset.countSleeps %lld", comment: ""), sleeps))
        }
        if diapers > 0 {
            parts.append(String(format: NSLocalizedString("settings.reset.countDiapers %lld", comment: ""), diapers))
        }
        if growths > 0 {
            parts.append(String(format: NSLocalizedString("settings.reset.countGrowth %lld", comment: ""), growths))
        }
        if milestones > 0 {
            parts.append(String(format: NSLocalizedString("settings.reset.countMilestones %lld", comment: ""), milestones))
        }

        // Join naturally: "A, B, and C"
        let andStr = NSLocalizedString("home.summary.and", comment: "")
        let commaAndStr = NSLocalizedString("home.summary.commaAnd", comment: "")
        let joined: String
        if parts.count == 1 {
            joined = parts[0]
        } else if parts.count == 2 {
            joined = "\(parts[0])\(andStr)\(parts[1])"
        } else {
            joined = "\(parts[0..<(parts.count - 1)].joined(separator: ", "))\(commaAndStr)\(parts[parts.count - 1])"
        }

        return String(format: NSLocalizedString("settings.reset.detailedMessage %@", comment: ""), joined)
    }

    // MARK: - Journey Stat Row

    private func journeyStatRow(icon: String, color: Color, label: String, count: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.blTextSecondary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(count > 0 ? .blTextPrimary : .blTextTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private func resetAllData() {
        // 1. Cancel all pending notifications and reset reminder state
        NotificationManager.shared.isEnabled = false  // cancels pending + writes UserDefaults
        feedingReminderEnabled = false
        feedingReminderInterval = 180

        // 2. Clear baby profile from UserDefaults
        UserDefaults.standard.removeObject(forKey: "currentBaby")
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")

        // 3. Batch-delete CoreData entities and merge into viewContext
        //    NSBatchDeleteRequest bypasses the MOC — without merging,
        //    @FetchRequest views hold stale objects that crash when faulted.
        let container = PersistenceController.shared.container
        let ctx = container.viewContext
        for entity in ["CDFeedingRecord", "CDSleepRecord", "CDDiaperRecord", "CDGrowthRecord", "CDMilestone"] {
            let req = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            let delete = NSBatchDeleteRequest(fetchRequest: req)
            delete.resultType = .resultTypeObjectIDs
            do {
                let result = try container.persistentStoreCoordinator.execute(delete, with: ctx) as? NSBatchDeleteResult
                if let objectIDs = result?.result as? [NSManagedObjectID], !objectIDs.isEmpty {
                    let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: objectIDs]
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [ctx])
                }
            } catch {
                // Fallback: reset the entire context if merge fails
                ctx.reset()
            }
        }

        // 4. Navigate to onboarding
        withAnimation {
            appState.hasCompletedOnboarding = false
            appState.currentBaby = nil
        }
    }
}

// MARK: - Journey Stats

/// Snapshot of aggregate record counts and tracking duration for the "Your Journey" section.
struct JourneyStats {
    let feedings: Int
    let sleeps: Int
    let diapers: Int
    let growths: Int
    let milestones: Int
    let firstRecordDate: Date?
    let currentStreak: Int
    let longestStreak: Int

    var totalRecords: Int { feedings + sleeps + diapers + growths + milestones }

    /// Human-readable tracking duration, e.g. "42 days" or "3 months"
    var trackingDurationText: String? {
        guard let first = firstRecordDate else { return nil }
        let cal = Calendar.current
        let components = cal.dateComponents([.month, .day], from: cal.startOfDay(for: first), to: cal.startOfDay(for: Date()))
        let months = components.month ?? 0
        let days = components.day ?? 0
        if months >= 1 {
            return String(format: NSLocalizedString("settings.journey.months %lld", comment: ""), months)
        } else if days >= 1 {
            return String(format: NSLocalizedString("settings.journey.days %lld", comment: ""), days)
        }
        return NSLocalizedString("settings.journey.today", comment: "")
    }

    static func load(ctx: NSManagedObjectContext) -> JourneyStats {
        func count(_ entity: String) -> Int {
            let req = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            return (try? ctx.count(for: req)) ?? 0
        }

        func earliest(_ entity: String, dateKey: String) -> Date? {
            let req = NSFetchRequest<NSManagedObject>(entityName: entity)
            req.sortDescriptors = [NSSortDescriptor(key: dateKey, ascending: true)]
            req.fetchLimit = 1
            req.propertiesToFetch = [dateKey]
            return (try? ctx.fetch(req))?.first?.value(forKey: dateKey) as? Date
        }

        let dates: [Date?] = [
            earliest("CDFeedingRecord", dateKey: "timestamp"),
            earliest("CDSleepRecord", dateKey: "startTime"),
            earliest("CDDiaperRecord", dateKey: "timestamp"),
            earliest("CDGrowthRecord", dateKey: "date"),
            earliest("CDMilestone", dateKey: "date")
        ]
        let firstDate = dates.compactMap { $0 }.min()

        // Compute logging streaks by collecting all unique record dates
        let streaks = computeStreaks(ctx: ctx)

        return JourneyStats(
            feedings: count("CDFeedingRecord"),
            sleeps: count("CDSleepRecord"),
            diapers: count("CDDiaperRecord"),
            growths: count("CDGrowthRecord"),
            milestones: count("CDMilestone"),
            firstRecordDate: firstDate,
            currentStreak: streaks.current,
            longestStreak: streaks.longest
        )
    }

    /// Collect all record dates, deduplicate by calendar day, then walk backwards
    /// from today to compute current streak and longest streak.
    private static func computeStreaks(ctx: NSManagedObjectContext) -> (current: Int, longest: Int) {
        let cal = Calendar.current

        func allDates(_ entity: String, dateKey: String) -> [Date] {
            let req = NSFetchRequest<NSManagedObject>(entityName: entity)
            req.propertiesToFetch = [dateKey]
            guard let results = try? ctx.fetch(req) else { return [] }
            return results.compactMap { $0.value(forKey: dateKey) as? Date }
        }

        // Gather all dates from every entity
        var rawDates: [Date] = []
        rawDates.append(contentsOf: allDates("CDFeedingRecord", dateKey: "timestamp"))
        rawDates.append(contentsOf: allDates("CDSleepRecord", dateKey: "startTime"))
        rawDates.append(contentsOf: allDates("CDDiaperRecord", dateKey: "timestamp"))
        rawDates.append(contentsOf: allDates("CDGrowthRecord", dateKey: "date"))
        rawDates.append(contentsOf: allDates("CDMilestone", dateKey: "date"))

        guard !rawDates.isEmpty else { return (0, 0) }

        // Convert to unique calendar days (as Date at start-of-day) and sort descending
        let uniqueDays: [Date] = Array(Set(rawDates.map { cal.startOfDay(for: $0) })).sorted(by: >)

        let today = cal.startOfDay(for: Date())

        // Current streak: count consecutive days backwards from today (or yesterday)
        var currentStreak = 0
        var expectedDay = today
        // Allow streak to start from yesterday if no records today
        if let first = uniqueDays.first, first != today {
            if cal.isDate(first, inSameDayAs: cal.date(byAdding: .day, value: -1, to: today)!) {
                expectedDay = first
            } else {
                // Gap > 1 day: no current streak
                // Still compute longest streak below
                currentStreak = 0
                expectedDay = today // won't match, so loop below won't increment
            }
        }

        for day in uniqueDays {
            if cal.isDate(day, inSameDayAs: expectedDay) {
                currentStreak += 1
                expectedDay = cal.date(byAdding: .day, value: -1, to: expectedDay)!
            } else if day < expectedDay {
                break
            }
        }

        // Longest streak: walk all sorted days
        let ascending = uniqueDays.reversed() // now ascending
        var longest = 0
        var streak = 0
        var prev: Date?
        for day in ascending {
            if let p = prev {
                let diff = cal.dateComponents([.day], from: p, to: day).day ?? 0
                if diff == 1 {
                    streak += 1
                } else if diff > 1 {
                    longest = max(longest, streak)
                    streak = 1
                }
                // diff == 0 shouldn't happen since we deduplicated
            } else {
                streak = 1
            }
            prev = day
        }
        longest = max(longest, streak)

        return (currentStreak, longest)
    }
}

// MARK: - Edit Baby
struct EditBabyView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var birthDate: Date = Date()
    @State private var gender: Baby.Gender = .girl
    @State private var photoData: Data?
    @State private var selectedPhoto: PhotosPickerItem?

    // Original values to detect unsaved changes
    @State private var originalName: String = ""
    @State private var originalBirthDate: Date = Date()
    @State private var originalGender: Baby.Gender = .girl
    @State private var originalPhotoData: Data?

    private var hasUnsavedChanges: Bool {
        name != originalName ||
        !Calendar.current.isDate(birthDate, inSameDayAs: originalBirthDate) ||
        gender != originalGender ||
        photoData != originalPhotoData
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.blBackground.ignoresSafeArea()
                Form {
                    // Photo section
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                // Current photo or placeholder
                                if let photoData, let uiImage = UIImage(data: photoData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 96, height: 96)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.blPrimary.opacity(0.3), lineWidth: 2)
                                        )
                                } else {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: gender.color).opacity(0.2))
                                            .frame(width: 96, height: 96)
                                        Text(gender.icon)
                                            .font(.system(size: 44))
                                    }
                                }

                                PhotosPicker(selection: $selectedPhoto,
                                             matching: .images,
                                             photoLibrary: .shared()) {
                                    HStack(spacing: 6) {
                                        Image(systemName: photoData != nil ? "arrow.triangle.2.circlepath.camera" : "camera.fill")
                                            .font(.system(size: 13, weight: .medium))
                                        Text(photoData != nil ? String(localized: "editBaby.changePhoto") : String(localized: "editBaby.addPhoto"))
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .foregroundColor(.blPrimary)
                                }

                                if photoData != nil {
                                    Button {
                                        withAnimation(.spring(response: 0.3)) {
                                            photoData = nil
                                            selectedPhoto = nil
                                        }
                                    } label: {
                                        Text(String(localized: "editBaby.removePhoto"))
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.blTextTertiary)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }

                    Section(String(localized: "editBaby.name")) {
                        TextField(String(localized: "editBaby.namePlaceholder"), text: $name)
                    }
                    Section(String(localized: "editBaby.birthday")) {
                        DatePicker(String(localized: "editBaby.birthday"), selection: $birthDate, in: ...Date(), displayedComponents: .date)
                    }
                    Section(String(localized: "editBaby.gender")) {
                        Picker(String(localized: "editBaby.gender"), selection: $gender) {
                            ForEach(Baby.Gender.allCases, id: \.self) { g in
                                Text("\(g.icon) \(g.displayName)").tag(g)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(String(localized: "editBaby.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(String(localized: "common.done")) {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save")) {
                        let trimmedName = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmedName.isEmpty else { return }
                        var baby = appState.currentBaby ?? Baby(name: trimmedName, birthDate: birthDate, gender: gender)
                        baby.name = trimmedName
                        baby.birthDate = birthDate
                        baby.gender = gender
                        baby.photoData = photoData
                        appState.saveBaby(baby)
                        Haptic.success()
                        appState.showToast(String(localized: "editBaby.saved"), icon: "checkmark.circle.fill", color: .blPrimary)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                }
            }
            .onAppear {
                if let baby = appState.currentBaby {
                    name = baby.name
                    birthDate = baby.birthDate
                    gender = baby.gender
                    photoData = baby.photoData
                    // Capture originals for change detection
                    originalName = baby.name
                    originalBirthDate = baby.birthDate
                    originalGender = baby.gender
                    originalPhotoData = baby.photoData
                }
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .onChange(of: selectedPhoto) { _, newItem in
                Task {
                    if let newItem,
                       let data = try? await newItem.loadTransferable(type: Data.self) {
                        // Downscale to avatar size then compress as JPEG.
                        // The avatar is shown at most 96pt (≈288px @3x).
                        // Keeping max dimension at 300px ensures the stored
                        // Data stays well under UserDefaults practical limits
                        // (~50–80 KB instead of potentially >1 MB for a full-
                        // resolution camera photo).
                        if let uiImage = UIImage(data: data),
                           let resized = Self.downsample(uiImage, maxDimension: 300),
                           let compressed = resized.jpegData(compressionQuality: 0.8) {
                            await MainActor.run {
                                withAnimation(.spring(response: 0.3)) {
                                    photoData = compressed
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

extension EditBabyView {
    /// Resize a UIImage so that its longest side is at most `maxDimension` points.
    /// Returns nil only when the graphics context cannot be created (extremely rare).
    static func downsample(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let longestSide = max(size.width, size.height)
        // Already small enough — return as-is
        guard longestSide > maxDimension else { return image }
        let scale = maxDimension / longestSide
        let newSize = CGSize(width: (size.width * scale).rounded(),
                             height: (size.height * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Share Sheet (UIKit bridge)
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
