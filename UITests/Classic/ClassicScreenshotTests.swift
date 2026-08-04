import XCTest

/// Walks every page of the classic (faithful-copy) frontend and captures
/// screenshots, in light and dark appearance.
final class ClassicScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func launch(dark: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"] + (dark ? ["-uitest-dark"] : [])
        app.launch()
        return app
    }

    func testLightModeWalkthrough() throws {
        let app = launch(dark: false)
        walkthrough(app, theme: "light", full: true)
    }

    func testDarkModeWalkthrough() throws {
        let app = launch(dark: true)
        walkthrough(app, theme: "dark", full: false)
    }

    private func walkthrough(_ app: XCUIApplication, theme: String, full: Bool) {
        // Home
        XCTAssertTrue(app.staticTexts["home.greeting"].waitForExistence(timeout: 15))
        snap("01-home__\(theme)")

        // SAT list (frequency sort default)
        app.buttons["home.list.SAT RW Vocab"].waitTap()
        XCTAssertTrue(app.otherElements["wordList.sortChips"].waitForExistence(timeout: 10)
            || app.collectionViews.firstMatch.waitForExistence(timeout: 10))
        snap("02-list-frequency__\(theme)")

        if full {
            // Familiarity sort
            app.buttons["wordList.sort.Familiarity"].waitTap()
            sleep(1)
            snap("03-list-familiarity__\(theme)")
            // Planned review sort
            app.buttons["wordList.sort.Planned Review"].waitTap()
            sleep(1)
            snap("04-list-planned__\(theme)")
            // Back to frequency for detail navigation
            app.buttons["wordList.sort.Frequency"].waitTap()
            sleep(1)
        }

        // Word detail: "some"
        app.staticTexts["some"].firstMatch.waitTap()
        XCTAssertTrue(app.otherElements["word.headerCard"].waitForExistence(timeout: 10))
        snap("05-word-related__\(theme)")

        if full {
            // Study info panel
            app.buttons["word.studyInfoToggle"].waitTap()
            sleep(1)
            snap("06-word-studyinfo__\(theme)")
            app.buttons["word.studyInfoToggle"].waitTap()

            // English definition tab
            let tabs = app.segmentedControls["word.tabs"]
            if tabs.waitForExistence(timeout: 5) {
                tabs.buttons["English definition"].tap()
                sleep(1)
                snap("07-word-english__\(theme)")
                tabs.buttons["Synonyms"].tap()
                sleep(1)
                snap("08-word-synonyms__\(theme)")
                tabs.buttons["Oxford"].tap()
                sleep(1)
                snap("09-word-oxford__\(theme)")
            }
        }

        // Back to list, then study start page
        app.navigationBars.buttons.firstMatch.waitTap()
        app.buttons["wordList.study"].waitTap()
        XCTAssertTrue(app.otherElements["study.start"].waitForExistence(timeout: 10)
            || app.staticTexts["Start with:"].waitForExistence(timeout: 10))
        snap("10-study-start__\(theme)")

        // Flashcard
        app.buttons["study.plan.Mix"].waitTap()
        XCTAssertTrue(app.staticTexts["New Word"].waitForExistence(timeout: 10)
            || app.staticTexts["Review"].waitForExistence(timeout: 10))
        snap("11-study-card__\(theme)")

        if full {
            // Reveal state
            app.buttons["study.know"].waitTap()
            sleep(1)
            snap("12-study-reveal__\(theme)")
        }

        // Leave the session (back), verify Continue Study appears
        app.navigationBars.buttons.firstMatch.waitTap()
        sleep(1)
        if full {
            snap("13-list-continue__\(theme)")
        }

        // Back home, My Words empty state
        app.navigationBars.buttons.firstMatch.waitTap()
        if full {
            app.buttons["home.myWords"].waitTap()
            sleep(1)
            snap("14-mywords-empty__\(theme)")
            app.navigationBars.buttons.firstMatch.waitTap()
        }

        // Settings
        app.buttons["home.settings"].waitTap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 10))
        snap("15-settings__\(theme)")

        if full {
            // Import words page
            app.buttons["settings.import"].waitTap()
            sleep(1)
            snap("16-import__\(theme)")
            app.navigationBars.buttons.firstMatch.waitTap()
            app.navigationBars.buttons.firstMatch.waitTap()

            // Search overlay: history then live result
            app.buttons["home.search"].waitTap()
            sleep(1)
            snap("17-search-history__\(theme)")
            let field = app.textFields["search.field"]
            if field.waitForExistence(timeout: 5) {
                field.tap()
                field.typeText("cordage")
                sleep(1)
                snap("18-search-results__\(theme)")
            }
            app.buttons["search.close"].waitTap()
        }
    }
}
