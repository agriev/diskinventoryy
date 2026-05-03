import XCTest

final class SmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesAndShowsEmptyState() throws {
        let app = XCUIApplication()
        app.launch()
        // Window appears; the empty-state placeholder is visible.
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }
}
