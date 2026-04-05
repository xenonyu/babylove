import XCTest

@MainActor
final class OnboardingUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--uitesting"]  // fresh state, no baby
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func testWelcomeScreenAppears() {
        XCTAssertTrue(app.buttons["Get Started"].waitForExistence(timeout: 5),
                      "Welcome screen should show 'Get Started' button")
    }

    func testWelcomeScreenHasAppName() {
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'BabyLove'"))
            .firstMatch.waitForExistence(timeout: 5))
    }

    func testNavigateToBabyInfoPage() {
        app.buttons["Get Started"].tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 3),
                      "Baby info page should show name text field")
    }

    func testContinueDisabledWithEmptyName() {
        app.buttons["Get Started"].tap()
        let continueBtn = app.buttons["Continue"]
        XCTAssertTrue(continueBtn.waitForExistence(timeout: 3))
        XCTAssertFalse(continueBtn.isEnabled, "Continue should be disabled with empty name")
    }

    func testContinueEnabledAfterName() {
        app.buttons["Get Started"].tap()
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Emma")
        let continueBtn = app.buttons["Continue"]
        XCTAssertTrue(continueBtn.isEnabled, "Continue should be enabled after entering name")
    }

    func testFullOnboardingFlow() {
        // Page 1: Welcome
        XCTAssertTrue(app.buttons["Get Started"].waitForExistence(timeout: 5))
        app.buttons["Get Started"].tap()

        // Page 2: Baby info
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Emma")
        app.buttons["Continue"].tap()

        // Page 3: All set
        let startBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Start'")).firstMatch
        XCTAssertTrue(startBtn.waitForExistence(timeout: 3), "Should reach 'All set' page")
        startBtn.tap()

        // Should see main tab bar
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5),
                      "Main tab bar should appear after onboarding")
    }
}
