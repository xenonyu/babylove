import CoreData
import Foundation

#if DEBUG
/// Injects realistic demo data for App Store screenshots.
/// Triggered by setting SEED_DEMO_DATA=1 environment variable.
struct DemoDataSeeder {

    static func seed(context: NSManagedObjectContext, appState: AppState) {
        clearAll(context: context)

        let birthDate = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 13))!
        let baby = Baby(name: "小宝", birthDate: birthDate, gender: .girl)
        appState.completeOnboarding(with: baby)

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        seedFeedings(context: context, today: today, cal: cal)
        seedSleeps(context: context, today: today, cal: cal)
        seedDiapers(context: context, today: today, cal: cal)
        seedGrowth(context: context, cal: cal)
        seedMilestones(context: context, cal: cal)

        try? context.save()
    }

    // MARK: - Private

    private static func clearAll(context: NSManagedObjectContext) {
        for entity in ["CDFeedingRecord", "CDSleepRecord", "CDDiaperRecord", "CDGrowthRecord", "CDMilestone"] {
            let req = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            let delete = NSBatchDeleteRequest(fetchRequest: req)
            try? context.execute(delete)
        }
        context.reset()
    }

    private static func dt(_ today: Date, day: Int, h: Int, m: Int, cal: Calendar) -> Date {
        let base = cal.date(byAdding: .day, value: day, to: today)!
        return cal.date(bySettingHour: h, minute: m, second: 0, of: base)!
    }

    // MARK: Feedings

    private static func seedFeedings(context: NSManagedObjectContext, today: Date, cal: Calendar) {
        // (dayOffset, hour, min, feedType, breastSide, durationMin, amountML)
        let rows: [(Int, Int, Int, String, String?, Int16, Double)] = [
            // Today
            (0,  6, 30, "breast",  "left",  15, 0),
            (0,  9,  0, "breast",  "right", 12, 0),
            (0, 11, 30, "formula", nil,      0, 90),
            (0, 14,  0, "breast",  "both",  18, 0),
            (0, 16, 30, "breast",  "left",  10, 0),
            (0, 19,  0, "formula", nil,      0, 80),
            // Yesterday
            (-1,  6,  0, "breast",  "right", 14, 0),
            (-1,  8, 30, "breast",  "left",  11, 0),
            (-1, 11,  0, "formula", nil,      0, 90),
            (-1, 13, 30, "breast",  "both",  16, 0),
            (-1, 16,  0, "breast",  "right", 13, 0),
            (-1, 18, 30, "formula", nil,      0, 85),
            (-1, 21,  0, "breast",  "left",   8, 0),
            // 2 days ago
            (-2,  5, 45, "breast",  "left",  12, 0),
            (-2,  8, 15, "breast",  "right", 14, 0),
            (-2, 11,  0, "formula", nil,      0, 90),
            (-2, 13, 30, "breast",  "left",  15, 0),
            (-2, 16,  0, "breast",  "both",  10, 0),
            (-2, 19,  0, "formula", nil,      0, 80),
            (-2, 22,  0, "breast",  "right",  9, 0),
            // 3 days ago
            (-3,  6, 30, "breast",  "left",  13, 0),
            (-3,  9,  0, "breast",  "right", 15, 0),
            (-3, 12,  0, "formula", nil,      0, 90),
            (-3, 14, 30, "breast",  "both",  17, 0),
            (-3, 17,  0, "breast",  "left",  11, 0),
            (-3, 20,  0, "formula", nil,      0, 85),
            // 4 days ago
            (-4,  6,  0, "breast",  "right", 12, 0),
            (-4,  9, 15, "formula", nil,      0, 90),
            (-4, 12,  0, "breast",  "left",  16, 0),
            (-4, 15,  0, "breast",  "both",  11, 0),
            (-4, 18,  0, "formula", nil,      0, 85),
            (-4, 21,  0, "breast",  "right", 10, 0),
            // 5 days ago
            (-5,  6, 30, "breast",  "left",  14, 0),
            (-5,  9,  0, "breast",  "right", 12, 0),
            (-5, 11, 30, "formula", nil,      0, 90),
            (-5, 14,  0, "breast",  "left",  15, 0),
            (-5, 17,  0, "breast",  "both",  10, 0),
            (-5, 20,  0, "formula", nil,      0, 80),
            // 6 days ago
            (-6,  6,  0, "breast",  "right", 13, 0),
            (-6,  8, 30, "formula", nil,      0, 90),
            (-6, 11,  0, "breast",  "left",  14, 0),
            (-6, 14,  0, "breast",  "right", 12, 0),
            (-6, 17,  0, "formula", nil,      0, 85),
            (-6, 20, 30, "breast",  "both",  11, 0),
        ]
        for (day, h, m, feed, side, dur, amt) in rows {
            let r = CDFeedingRecord(context: context)
            r.id = UUID()
            r.timestamp = dt(today, day: day, h: h, m: m, cal: cal)
            r.feedType = feed
            r.breastSide = side
            r.durationMinutes = dur
            r.amountML = amt
        }
    }

    // MARK: Sleeps

    private static func seedSleeps(context: NSManagedObjectContext, today: Date, cal: Calendar) {
        // (startDay, sh, sm, endDay, eh, em, location)
        let rows: [(Int, Int, Int, Int, Int, Int, String)] = [
            // Night before today
            (-1, 21, 30,  0,  6,  0, "crib"),
            // Today's naps
            ( 0,  7,  0,  0,  8, 45, "crib"),
            ( 0, 11,  0,  0, 12, 30, "bassinet"),
            ( 0, 14, 30,  0, 16,  0, "stroller"),
            // Night before yesterday
            (-2, 21,  0, -1,  5, 45, "crib"),
            // Yesterday's naps
            (-1,  7, 30, -1,  9,  0, "crib"),
            (-1, 12,  0, -1, 13, 30, "bassinet"),
            (-1, 15,  0, -1, 16, 30, "carrier"),
            // 2 days ago
            (-3, 21, 30, -2,  6,  0, "crib"),
            (-2,  8,  0, -2,  9, 30, "crib"),
            (-2, 12, 30, -2, 14,  0, "bassinet"),
            (-2, 16, 30, -2, 17, 30, "stroller"),
            // 3 days ago
            (-4, 21,  0, -3,  6,  0, "crib"),
            (-3,  7, 30, -3,  9,  0, "crib"),
            (-3, 12,  0, -3, 13, 30, "bassinet"),
            (-3, 15, 30, -3, 17,  0, "carrier"),
            // 4 days ago
            (-5, 21, 30, -4,  6,  0, "crib"),
            (-4,  8,  0, -4,  9, 30, "crib"),
            (-4, 13,  0, -4, 14, 30, "bassinet"),
            (-4, 16,  0, -4, 17, 30, "stroller"),
            // 5 days ago
            (-6, 21,  0, -5,  5, 45, "crib"),
            (-5,  7, 30, -5,  9,  0, "crib"),
            (-5, 12,  0, -5, 13, 30, "bassinet"),
            (-5, 15,  0, -5, 16, 30, "carrier"),
        ]
        for (sd, sh, sm, ed, eh, em, loc) in rows {
            let r = CDSleepRecord(context: context)
            r.id = UUID()
            r.startTime = dt(today, day: sd, h: sh, m: sm, cal: cal)
            r.endTime   = dt(today, day: ed, h: eh, m: em, cal: cal)
            r.location  = loc
        }
    }

    // MARK: Diapers

    private static func seedDiapers(context: NSManagedObjectContext, today: Date, cal: Calendar) {
        let rows: [(Int, Int, Int, String)] = [
            // Today
            (0,  7, 15, "wet"),
            (0,  9, 30, "dirty"),
            (0, 12,  0, "wet"),
            (0, 15,  0, "both"),
            (0, 17, 30, "wet"),
            // Yesterday
            (-1,  6, 30, "wet"),
            (-1,  9,  0, "dirty"),
            (-1, 11, 30, "wet"),
            (-1, 14,  0, "both"),
            (-1, 16, 30, "wet"),
            (-1, 19, 30, "dirty"),
            // 2 days ago
            (-2,  7,  0, "wet"),
            (-2,  9, 30, "wet"),
            (-2, 12,  0, "dirty"),
            (-2, 15,  0, "both"),
            (-2, 18,  0, "wet"),
            // 3 days ago
            (-3,  7, 15, "wet"),
            (-3, 10,  0, "dirty"),
            (-3, 13,  0, "wet"),
            (-3, 16,  0, "both"),
            (-3, 19,  0, "wet"),
            // 4 days ago
            (-4,  7,  0, "wet"),
            (-4,  9, 30, "dirty"),
            (-4, 12,  0, "wet"),
            (-4, 15,  0, "both"),
            (-4, 18, 30, "wet"),
            // 5 days ago
            (-5,  6, 45, "wet"),
            (-5,  9,  0, "dirty"),
            (-5, 12, 30, "wet"),
            (-5, 15,  0, "both"),
            (-5, 18,  0, "wet"),
            // 6 days ago
            (-6,  7,  0, "wet"),
            (-6,  9, 30, "dirty"),
            (-6, 13,  0, "both"),
            (-6, 16,  0, "wet"),
            (-6, 19, 30, "wet"),
        ]
        for (day, h, m, t) in rows {
            let r = CDDiaperRecord(context: context)
            r.id = UUID()
            r.timestamp = dt(today, day: day, h: h, m: m, cal: cal)
            r.diaperType = t
        }
    }

    // MARK: Growth

    private static func seedGrowth(context: NSManagedObjectContext, cal: Calendar) {
        let rows: [(Int, Int, Int, Double, Double, Double)] = [
            (2026, 1, 13, 3.20, 50.0, 34.0),  // birth
            (2026, 2, 13, 4.50, 55.0, 37.0),  // 1 month
            (2026, 3, 13, 5.80, 58.5, 39.5),  // 2 months
            (2026, 4, 10, 6.50, 61.0, 41.0),  // 3 months
        ]
        for (y, mo, d, wt, ht, hc) in rows {
            let r = CDGrowthRecord(context: context)
            r.id = UUID()
            r.date = cal.date(from: DateComponents(year: y, month: mo, day: d))!
            r.weightKG = wt
            r.heightCM = ht
            r.headCircumferenceCM = hc
        }
    }

    // MARK: Milestones

    private static func seedMilestones(context: NSManagedObjectContext, cal: Calendar) {
        let rows: [(String, String, Int, Int, Int)] = [
            ("First Smile",          "social",    2026, 2, 20),
            ("Holds Head Up",        "motor",     2026, 3,  1),
            ("Recognizes Parents",   "social",    2026, 2, 28),
            ("Coos & Babbles",       "language",  2026, 3, 15),
            ("Reaches for Objects",  "motor",     2026, 4,  5),
            ("First Bath",           "health",    2026, 1, 15),
        ]
        for (title, cat, y, mo, d) in rows {
            let r = CDMilestone(context: context)
            r.id = UUID()
            r.title = title
            r.category = cat
            r.date = cal.date(from: DateComponents(year: y, month: mo, day: d))!
            r.isCompleted = true
        }
    }
}
#endif
