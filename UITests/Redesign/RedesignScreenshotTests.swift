import XCTest

/// Screenshot pass for the redesigned frontend. Grows to a full walkthrough
/// as the redesign lands; for now it verifies launch and captures the home
/// scaffold.
final class RedesignScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testLightHome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Voccab"].waitForExistence(timeout: 15))
        snap("01-home__light")
    }

    func testDarkHome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-uitest-dark"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Voccab"].waitForExistence(timeout: 15))
        snap("01-home__dark")
    }
}
