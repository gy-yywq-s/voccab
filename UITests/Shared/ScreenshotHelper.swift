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
