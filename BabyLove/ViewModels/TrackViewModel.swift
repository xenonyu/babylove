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
                    notes: String = "",
                    timestamp: Date = Date()) {
        let record = CDFeedingRecord(context: ctx)
        record.id = UUID()
        record.timestamp = timestamp
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

    func endSleepByID(_ id: UUID, context: NSManagedObjectContext) {
        let req: NSFetchRequest<CDSleepRecord> = CDSleepRecord.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let record = (try? context.fetch(req))?.first else { return }
        record.endTime = Date()
        try? context.save()
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

    func logDiaper(type: DiaperType, notes: String = "", timestamp: Date = Date()) {
        let record = CDDiaperRecord(context: ctx)
        record.id = UUID()
        record.timestamp = timestamp
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

    // MARK: - Update Feeding

    func updateFeeding(_ record: CDFeedingRecord,
                       type: FeedType,
                       side: BreastSide? = nil,
                       durationMinutes: Int = 0,
                       amountML: Double = 0,
                       notes: String = "",
                       timestamp: Date) {
        record.feedType = type.rawValue
        record.breastSide = side?.rawValue
        record.durationMinutes = Int16(durationMinutes)
        record.amountML = amountML
        record.timestamp = timestamp
        record.notes = notes.isEmpty ? nil : notes
        save()
    }

    // MARK: - Update Sleep

    func updateSleep(_ record: CDSleepRecord,
                     start: Date,
                     end: Date?,
                     location: SleepLocation,
                     notes: String = "") {
        record.startTime = start
        record.endTime = end
        record.location = location.rawValue
        record.notes = notes.isEmpty ? nil : notes
        save()
    }

    // MARK: - Update Diaper

    func updateDiaper(_ record: CDDiaperRecord,
                      type: DiaperType,
                      notes: String = "",
                      timestamp: Date) {
        record.diaperType = type.rawValue
        record.timestamp = timestamp
        record.notes = notes.isEmpty ? nil : notes
        save()
    }

    // MARK: - Update Growth

    func updateGrowth(_ record: CDGrowthRecord,
                      weightKG: Double? = nil,
                      heightCM: Double? = nil,
                      headCM: Double? = nil,
                      notes: String = "") {
        record.weightKG = weightKG ?? 0
        record.heightCM = heightCM ?? 0
        record.headCircumferenceCM = headCM ?? 0
        record.date = record.date ?? Date()
        record.notes = notes.isEmpty ? nil : notes
        save()
    }

    // MARK: - Delete

    func deleteObject(_ object: NSManagedObject) {
        ctx.delete(object)
        save()
    }

    func deleteObject(_ object: NSManagedObject, in context: NSManagedObjectContext) {
        context.delete(object)
        try? context.save()
    }

    private func save() {
        guard ctx.hasChanges else { return }
        try? ctx.save()
    }
}
