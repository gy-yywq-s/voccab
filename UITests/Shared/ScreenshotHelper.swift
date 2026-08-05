import XCTest

extension XCTestCase {
    /// Saves a full-screen PNG into the test results with a stable name.
    /// CI exports these attachments and pushes them to the ci-screenshots
    /// branch for visual review.
    func snap(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(
            uniformTypeIdentifier: "public.png",
            name: "\(name).png",
            payload: screenshot.pngRepresentation,
            userInfo: nil
        )
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension XCUIElement {
    @discardableResult
    func waitTap(timeout: TimeInterval = 8) -> Bool {
        guard waitForExistence(timeout: timeout) else { return false }
        tap()
        return true
    }
}

extension XCTestCase {
    /// Polls every plausible surfacing of the graded answer row (identifier
    /// or visible label, button or consumed static text) — SwiftUI styled
    /// buttons expose differently per frontend.
    func waitForGradeRow(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.buttons["study.grade.1"].exists
                || app.buttons["Again"].exists
                || app.staticTexts["Again"].exists
                || app.descendants(matching: .any)["study.grade.1"].firstMatch.exists {
                return true
            }
            usleep(500_000)
        }
        return false
    }
}
