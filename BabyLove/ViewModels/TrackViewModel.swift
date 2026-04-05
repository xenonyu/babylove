import CoreData
import SwiftUI

class TrackViewModel: ObservableObject {
    private let ctx: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.ctx = context
    }

    // MARK: - Feeding

    func logFeeding(type: FeedType,
                    side: BreastSide? = nil,
                    durationMinutes: Int = 0,
                    amountML: Double = 0,
                    notes: String = "") {
        let record = CDFeedingRecord(context: ctx)
        record.id = UUID()
        record.timestamp = Date()
        record.feedType = type.rawValue
        record.breastSide = side?.rawValue
        record.durationMinutes = Int16(durationMinutes)
        record.amountML = amountML
        record.notes = notes.isEmpty ? nil : notes
        save()
    }

    // MARK: - Sleep

    func startSleep(location: SleepLocation = .crib, notes: String = "") -> CDSleepRecord {
        let record = CDSleepRecord(context: ctx)
        record.id = UUID()
        record.startTime = Date()
        record.location = location.rawValue
        record.notes = notes.isEmpty ? nil : notes
        save()
        return record
    }

    func endSleep(_ record: CDSleepRecord) {
        record.endTime = Date()
        save()
    }

    func logSleep(start: Date, end: Date, location: SleepLocation = .crib, notes: String = "") {
        let record = CDSleepRecord(context: ctx)
        record.id = UUID()
        record.startTime = start
        record.endTime = end
        record.location = location.rawValue
        record.notes = notes.isEmpty ? nil : notes
        save()
    }

    // MARK: - Diaper

    func logDiaper(type: DiaperType, notes: String = "") {
        let record = CDDiaperRecord(context: ctx)
        record.id = UUID()
        record.timestamp = Date()
        record.diaperType = type.rawValue
        record.notes = notes.isEmpty ? nil : notes
        save()
    }

    // MARK: - Growth

    func logGrowth(weightKG: Double? = nil,
                   heightCM: Double? = nil,
                   headCM: Double? = nil,
                   notes: String = "") {
        let record = CDGrowthRecord(context: ctx)
        record.id = UUID()
        record.date = Date()
        if let w = weightKG { record.weightKG = w }
        if let h = heightCM { record.heightCM = h }
        if let hc = headCM  { record.headCircumferenceCM = hc }
        record.notes = notes.isEmpty ? nil : notes
        save()
    }

    // MARK: - Milestone

    func addMilestone(title: String,
                      category: MilestoneCategory,
                      date: Date = Date(),
                      notes: String = "") {
        let m = CDMilestone(context: ctx)
        m.id = UUID()
        m.title = title
        m.category = category.rawValue
        m.date = date
        m.notes = notes.isEmpty ? nil : notes
        m.isCompleted = true
        save()
    }

    // MARK: - Today Stats

    func todayFeedings(context: NSManagedObjectContext) -> Int {
        let req: NSFetchRequest<CDFeedingRecord> = CDFeedingRecord.fetchRequest()
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        req.predicate = NSPredicate(format: "timestamp >= %@", start as NSDate)
        return (try? context.count(for: req)) ?? 0
    }

    func todaySleepMinutes(context: NSManagedObjectContext) -> Int {
        let req: NSFetchRequest<CDSleepRecord> = CDSleepRecord.fetchRequest()
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        req.predicate = NSPredicate(format: "startTime >= %@", start as NSDate)
        let records = (try? context.fetch(req)) ?? []
        let total = records.reduce(0) { sum, r in
            guard let s = r.startTime, let e = r.endTime else { return sum }
            return sum + Int(e.timeIntervalSince(s) / 60)
        }
        return total
    }

    func todayDiapers(context: NSManagedObjectContext) -> Int {
        let req: NSFetchRequest<CDDiaperRecord> = CDDiaperRecord.fetchRequest()
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        req.predicate = NSPredicate(format: "timestamp >= %@", start as NSDate)
        return (try? context.count(for: req)) ?? 0
    }

    private func save() {
        guard ctx.hasChanges else { return }
        try? ctx.save()
    }
}
