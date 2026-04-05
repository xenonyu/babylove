import XCTest
import CoreData
@testable import BabyLove

final class TrackViewModelTests: XCTestCase {
    var context: NSManagedObjectContext!
    var vm: TrackViewModel!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        vm = TrackViewModel(context: context)
    }

    override func tearDownWithError() throws {
        context = nil
        vm = nil
    }

    // MARK: - Feeding

    func testLogBreastFeeding() throws {
        vm.logFeeding(type: .breast, side: .left, durationMinutes: 15, amountML: 0)
        let results = try context.fetch(CDFeedingRecord.fetchRequest())
        XCTAssertEqual(results.count, 1)
        let r = results[0]
        XCTAssertEqual(r.feedType, "breast")
        XCTAssertEqual(r.breastSide, "left")
        XCTAssertEqual(r.durationMinutes, 15)
        XCTAssertNotNil(r.id)
        XCTAssertNotNil(r.timestamp)
    }

    func testLogFormulaFeeding() throws {
        vm.logFeeding(type: .formula, amountML: 120)
        let results = try context.fetch(CDFeedingRecord.fetchRequest())
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].feedType, "formula")
        XCTAssertEqual(results[0].amountML, 120, accuracy: 0.01)
    }

    func testMultipleFeedingsToday() throws {
        vm.logFeeding(type: .breast, durationMinutes: 10)
        vm.logFeeding(type: .breast, durationMinutes: 12)
        vm.logFeeding(type: .formula, amountML: 80)
        XCTAssertEqual(vm.todayFeedings(context: context), 3)
    }

    func testFeedingNotes() throws {
        vm.logFeeding(type: .solid, notes: "Tried banana")
        let results = try context.fetch(CDFeedingRecord.fetchRequest())
        XCTAssertEqual(results[0].notes, "Tried banana")
    }

    func testEmptyNotesStoredAsNil() throws {
        vm.logFeeding(type: .breast, notes: "")
        let results = try context.fetch(CDFeedingRecord.fetchRequest())
        XCTAssertNil(results[0].notes)
    }

    // MARK: - Sleep

    func testLogCompletedSleep() throws {
        let start = Date().addingTimeInterval(-3600)
        let end   = Date()
        vm.logSleep(start: start, end: end, location: .crib)
        let results = try context.fetch(CDSleepRecord.fetchRequest())
        XCTAssertEqual(results.count, 1)
        let r = results[0]
        XCTAssertEqual(r.location, "crib")
        XCTAssertNotNil(r.startTime)
        XCTAssertNotNil(r.endTime)
    }

    func testStartOngoingSleep() throws {
        _ = vm.startSleep(location: .bassinet)
        let results = try context.fetch(CDSleepRecord.fetchRequest())
        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results[0].endTime)  // no end time yet
        XCTAssertEqual(results[0].location, "bassinet")
    }

    func testSleepDurationCalculation() {
        let start = Date().addingTimeInterval(-5400) // 90 min ago
        let end   = Date()
        vm.logSleep(start: start, end: end, location: .crib)
        let totalMins = vm.todaySleepMinutes(context: context)
        XCTAssertGreaterThan(totalMins, 80)
        XCTAssertLessThan(totalMins, 100)
    }

    // MARK: - Diaper

    func testLogWetDiaper() throws {
        vm.logDiaper(type: .wet)
        let results = try context.fetch(CDDiaperRecord.fetchRequest())
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].diaperType, "wet")
        XCTAssertNotNil(results[0].timestamp)
    }

    func testMultipleDiaperTypes() throws {
        vm.logDiaper(type: .wet)
        vm.logDiaper(type: .dirty)
        vm.logDiaper(type: .both)
        XCTAssertEqual(vm.todayDiapers(context: context), 3)
    }

    // MARK: - Growth

    func testLogGrowthAllMetrics() throws {
        vm.logGrowth(weightKG: 5.5, heightCM: 60.2, headCM: 40.1)
        let results = try context.fetch(CDGrowthRecord.fetchRequest())
        XCTAssertEqual(results.count, 1)
        let r = results[0]
        XCTAssertEqual(r.weightKG, 5.5, accuracy: 0.001)
        XCTAssertEqual(r.heightCM, 60.2, accuracy: 0.001)
        XCTAssertEqual(r.headCircumferenceCM, 40.1, accuracy: 0.001)
    }

    func testLogGrowthPartialMetrics() throws {
        vm.logGrowth(weightKG: 6.1)
        let results = try context.fetch(CDGrowthRecord.fetchRequest())
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].weightKG, 6.1, accuracy: 0.001)
        XCTAssertEqual(results[0].heightCM, 0.0, accuracy: 0.001)
    }

    // MARK: - Milestone

    func testAddMilestone() throws {
        vm.addMilestone(title: "First smile", category: .social, notes: "So cute!")
        let results = try context.fetch(CDMilestone.fetchRequest())
        XCTAssertEqual(results.count, 1)
        let m = results[0]
        XCTAssertEqual(m.title, "First smile")
        XCTAssertEqual(m.category, "social")
        XCTAssertTrue(m.isCompleted)
        XCTAssertEqual(m.notes, "So cute!")
    }

    func testMilestoneDateIsToday() throws {
        vm.addMilestone(title: "First steps", category: .motor)
        let results = try context.fetch(CDMilestone.fetchRequest())
        let date = try XCTUnwrap(results[0].date)
        let diff = abs(date.timeIntervalSinceNow)
        XCTAssertLessThan(diff, 5) // within 5 seconds
    }

    // MARK: - Today Stats (boundary: records from yesterday don't count)

    func testYesterdayFeedingsNotCounted() throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let r = CDFeedingRecord(context: context)
        r.id = UUID()
        r.timestamp = yesterday
        r.feedType = "breast"
        try context.save()
        XCTAssertEqual(vm.todayFeedings(context: context), 0)
    }
}
