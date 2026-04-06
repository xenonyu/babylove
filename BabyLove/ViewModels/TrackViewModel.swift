import CoreData
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.babylove.app", category: "TrackViewModel")

class TrackViewModel: ObservableObject {
    private let ctx: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.ctx = context
    }

    /// Trim whitespace/newlines; return nil if result is empty.
    private func trimmedOrNil(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    // MARK: - Feeding

    @discardableResult
    func logFeeding(type: FeedType,
                    side: BreastSide? = nil,
                    durationMinutes: Int = 0,
                    amountML: Double = 0,
                    notes: String = "",
                    timestamp: Date = Date()) -> Bool {
        let record = CDFeedingRecord(context: ctx)
        record.id = UUID()
        record.timestamp = timestamp
        record.feedType = type.rawValue
        record.breastSide = side?.rawValue
        record.durationMinutes = Int16(durationMinutes)
        record.amountML = amountML
        record.notes = trimmedOrNil(notes)
        let ok = save()
        if ok {
            // Schedule next feeding reminder based on this feeding's timestamp
            Task { @MainActor in
                NotificationManager.shared.scheduleFeedingReminder(afterFeedingAt: timestamp)
            }
        }
        return ok
    }

    // MARK: - Feeding Timer (Ongoing)

    /// Start an ongoing breast/pump feeding. Saves with durationMinutes = 0 to indicate "in progress".
    @discardableResult
    func startFeeding(type: FeedType, side: BreastSide? = nil, notes: String = "", timestamp: Date = Date()) -> Bool {
        let record = CDFeedingRecord(context: ctx)
        record.id = UUID()
        record.timestamp = timestamp
        record.feedType = type.rawValue
        record.breastSide = side?.rawValue
        record.durationMinutes = 0  // 0 = ongoing for breast/pump
        record.amountML = 0
        record.notes = trimmedOrNil(notes)
        return save()
    }

    /// End an ongoing feeding by ID, computing duration from timestamp to now.
    @discardableResult
    func endFeedingByID(_ id: UUID, context: NSManagedObjectContext) -> Bool {
        let req: NSFetchRequest<CDFeedingRecord> = CDFeedingRecord.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let record = (try? context.fetch(req))?.first,
              let start = record.timestamp else { return false }
        let minutes = max(1, Int(Date().timeIntervalSince(start) / 60))
        record.durationMinutes = Int16(minutes)
        let ok = Self.save(context)
        if ok {
            // Schedule next feeding reminder from now (when the feeding ended)
            Task { @MainActor in
                NotificationManager.shared.scheduleFeedingReminder(afterFeedingAt: Date())
            }
        }
        return ok
    }

    // MARK: - Sleep

    @discardableResult
    func startSleep(at startTime: Date = Date(), location: SleepLocation = .crib, notes: String = "") -> Bool {
        let record = CDSleepRecord(context: ctx)
        record.id = UUID()
        record.startTime = startTime
        record.location = location.rawValue
        record.notes = trimmedOrNil(notes)
        return save()
    }

    @discardableResult
    func endSleep(_ record: CDSleepRecord) -> Bool {
        record.endTime = Date()
        return save()
    }

    @discardableResult
    func endSleepByID(_ id: UUID, context: NSManagedObjectContext) -> Bool {
        let req: NSFetchRequest<CDSleepRecord> = CDSleepRecord.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let record = (try? context.fetch(req))?.first else { return false }
        record.endTime = Date()
        return Self.save(context)
    }

    @discardableResult
    func logSleep(start: Date, end: Date, location: SleepLocation = .crib, notes: String = "") -> Bool {
        let record = CDSleepRecord(context: ctx)
        record.id = UUID()
        record.startTime = start
        record.endTime = end
        record.location = location.rawValue
        record.notes = trimmedOrNil(notes)
        return save()
    }

    // MARK: - Diaper

    @discardableResult
    func logDiaper(type: DiaperType, notes: String = "", timestamp: Date = Date()) -> Bool {
        let record = CDDiaperRecord(context: ctx)
        record.id = UUID()
        record.timestamp = timestamp
        record.diaperType = type.rawValue
        record.notes = trimmedOrNil(notes)
        return save()
    }

    // MARK: - Growth

    @discardableResult
    func logGrowth(weightKG: Double? = nil,
                   heightCM: Double? = nil,
                   headCM: Double? = nil,
                   date: Date = Date(),
                   notes: String = "") -> Bool {
        let record = CDGrowthRecord(context: ctx)
        record.id = UUID()
        record.date = date
        if let w = weightKG { record.weightKG = w }
        if let h = heightCM { record.heightCM = h }
        if let hc = headCM  { record.headCircumferenceCM = hc }
        record.notes = trimmedOrNil(notes)
        return save()
    }

    // MARK: - Milestone

    @discardableResult
    func addMilestone(title: String,
                      category: MilestoneCategory,
                      date: Date = Date(),
                      notes: String = "",
                      isCompleted: Bool = true) -> Bool {
        let m = CDMilestone(context: ctx)
        m.id = UUID()
        m.title = title
        m.category = category.rawValue
        m.date = date
        m.notes = trimmedOrNil(notes)
        m.isCompleted = isCompleted
        return save()
    }

    @discardableResult
    func updateMilestone(_ record: CDMilestone,
                         title: String,
                         category: MilestoneCategory,
                         date: Date,
                         notes: String = "",
                         isCompleted: Bool = true) -> Bool {
        record.title = title
        record.category = category.rawValue
        record.date = date
        record.notes = trimmedOrNil(notes)
        record.isCompleted = isCompleted
        return save()
    }

    @discardableResult
    func toggleMilestoneCompleted(_ record: CDMilestone, in context: NSManagedObjectContext) -> Bool {
        record.isCompleted.toggle()
        return Self.save(context)
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

    @discardableResult
    func updateFeeding(_ record: CDFeedingRecord,
                       type: FeedType,
                       side: BreastSide? = nil,
                       durationMinutes: Int = 0,
                       amountML: Double = 0,
                       notes: String = "",
                       timestamp: Date) -> Bool {
        record.feedType = type.rawValue
        record.breastSide = side?.rawValue
        record.durationMinutes = Int16(durationMinutes)
        record.amountML = amountML
        record.timestamp = timestamp
        record.notes = trimmedOrNil(notes)
        let ok = save()
        if ok {
            // Re-schedule feeding reminder based on updated timestamp
            Task { @MainActor in
                NotificationManager.shared.scheduleFeedingReminder(afterFeedingAt: timestamp)
            }
        }
        return ok
    }

    // MARK: - Update Sleep

    @discardableResult
    func updateSleep(_ record: CDSleepRecord,
                     start: Date,
                     end: Date?,
                     location: SleepLocation,
                     notes: String = "") -> Bool {
        record.startTime = start
        record.endTime = end
        record.location = location.rawValue
        record.notes = trimmedOrNil(notes)
        return save()
    }

    // MARK: - Update Diaper

    @discardableResult
    func updateDiaper(_ record: CDDiaperRecord,
                      type: DiaperType,
                      notes: String = "",
                      timestamp: Date) -> Bool {
        record.diaperType = type.rawValue
        record.timestamp = timestamp
        record.notes = trimmedOrNil(notes)
        return save()
    }

    // MARK: - Update Growth

    @discardableResult
    func updateGrowth(_ record: CDGrowthRecord,
                      weightKG: Double? = nil,
                      heightCM: Double? = nil,
                      headCM: Double? = nil,
                      date: Date = Date(),
                      notes: String = "") -> Bool {
        // Preserve existing values when a field is not provided (nil),
        // but allow explicit zero to clear a measurement.
        record.weightKG = weightKG ?? record.weightKG
        record.heightCM = heightCM ?? record.heightCM
        record.headCircumferenceCM = headCM ?? record.headCircumferenceCM
        record.date = date
        record.notes = trimmedOrNil(notes)
        return save()
    }

    // MARK: - Delete

    @discardableResult
    func deleteObject(_ object: NSManagedObject) -> Bool {
        ctx.delete(object)
        return save()
    }

    @discardableResult
    func deleteObject(_ object: NSManagedObject, in context: NSManagedObjectContext) -> Bool {
        context.delete(object)
        return Self.save(context)
    }

    // MARK: - Private Save

    @discardableResult
    private func save() -> Bool {
        guard ctx.hasChanges else { return true }
        do {
            try ctx.save()
            return true
        } catch {
            logger.error("CoreData save failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Save on an arbitrary context (used by byID helpers and delete).
    @discardableResult
    private static func save(_ context: NSManagedObjectContext) -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            logger.error("CoreData save failed: \(error.localizedDescription)")
            return false
        }
    }
}
