import XCTest

@MainActor
final class MainTabUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--uitesting", "--skip-onboarding"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - Tab Navigation

    func testAllTabsExist() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.buttons["Today"].exists)
        XCTAssertTrue(tabBar.buttons["Track"].exists)
        XCTAssertTrue(tabBar.buttons["Growth"].exists)
        XCTAssertTrue(tabBar.buttons["Memories"].exists)
        XCTAssertTrue(tabBar.buttons["More"].exists)
    }

    func testTrackTabNavigation() {
        app.tabBars.firstMatch.buttons["Track"].tap()
        XCTAssertTrue(app.navigationBars["Track"].waitForExistence(timeout: 3))
    }

    func testGrowthTabNavigation() {
        app.tabBars.firstMatch.buttons["Growth"].tap()
        XCTAssertTrue(app.navigationBars["Growth"].waitForExistence(timeout: 3))
    }

    func testMemoriesTabNavigation() {
        app.tabBars.firstMatch.buttons["Memories"].tap()
        XCTAssertTrue(app.navigationBars["Memories"].waitForExistence(timeout: 3))
    }

    func testSettingsTabNavigation() {
        app.tabBars.firstMatch.buttons["More"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    // MARK: - Feeding Log

    func testFeedingLogOpens() {
        app.tabBars.firstMatch.buttons["Track"].tap()
        app.buttons["Feeding"].tap()
        XCTAssertTrue(app.navigationBars["Log Feeding"].waitForExistence(timeout: 3))
    }

    func testFeedingLogCanBeDismissed() {
        app.tabBars.firstMatch.buttons["Track"].tap()
        app.buttons["Feeding"].tap()
        XCTAssertTrue(app.navigationBars["Log Feeding"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Track"].waitForExistence(timeout: 3))
    }

    func testFeedingLogSubmit() {
        app.tabBars.firstMatch.buttons["Track"].tap()
        app.buttons["Feeding"].tap()
        XCTAssertTrue(app.navigationBars["Log Feeding"].waitForExistence(timeout: 3))
        app.buttons["Log Feeding"].tap()
        // Should dismiss and return to Track
        XCTAssertTrue(app.navigationBars["Track"].waitForExistence(timeout: 3))
    }

    // MARK: - Sleep Log

    func testSleepLogOpens() {
        app.tabBars.firstMatch.buttons["Track"].tap()
        app.buttons["Sleep"].tap()
        XCTAssertTrue(app.navigationBars["Log Sleep"].waitForExistence(timeout: 3))
    }

    func testSleepLogSubmit() {
        app.tabBars.firstMatch.buttons["Track"].tap()
        app.buttons["Sleep"].tap()
        XCTAssertTrue(app.navigationBars["Log Sleep"].waitForExistence(timeout: 3))
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sleep'")).element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Track"].waitForExistence(timeout: 3))
    }

    // MARK: - Diaper Log

    func testDiaperLogOpens() {
        app.tabBars.firstMatch.buttons["Track"].tap()
        app.buttons["Diaper"].tap()
        XCTAssertTrue(app.navigationBars["Log Diaper"].waitForExistence(timeout: 3))
    }

    func testDiaperLogSubmit() {
        app.tabBars.firstMatch.buttons["Track"].tap()
        app.buttons["Diaper"].tap()
        XCTAssertTrue(app.navigationBars["Log Diaper"].waitForExistence(timeout: 3))
        app.buttons["Log Diaper Change"].tap()
        XCTAssertTrue(app.navigationBars["Track"].waitForExistence(timeout: 3))
    }

    // MARK: - Growth

    func testGrowthAddButtonExists() {
        app.tabBars.firstMatch.buttons["Growth"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Add' OR label CONTAINS 'plus'")).firstMatch.waitForExistence(timeout: 3))
    }

    // MARK: - Memories

    func testMemoriesAddMilestoneOpens() {
        app.tabBars.firstMatch.buttons["Memories"].tap()
        // Either see the "Add First Milestone" button or the + nav button
        let addBtn = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Milestone' OR label CONTAINS 'plus'")
        ).firstMatch
        XCTAssertTrue(addBtn.waitForExistence(timeout: 3))
    }

    // MARK: - Screenshot capture (non-blocking, best-effort)

    func testCaptureHomeScreenshot() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "home-screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCaptureTrackScreenshot() {
        app.tabBars.firstMatch.buttons["Track"].tap()
        XCTAssertTrue(app.navigationBars["Track"].waitForExistence(timeout: 3))
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "track-screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCaptureGrowthScreenshot() {
        app.tabBars.firstMatch.buttons["Growth"].tap()
        XCTAssertTrue(app.navigationBars["Growth"].waitForExistence(timeout: 3))
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "growth-screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
