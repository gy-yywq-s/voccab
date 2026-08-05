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

    /// The 3-button graded input (Again / Good / Easy) on the flashcard.
    func testThreeButtonPractice() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-settings.answerStyle", "threeButtons"]
        app.launch()
        // Generous waits everywhere: this is the third launch in the run and
        // the simulator can be very slow; the screenshot is the evidence.
        _ = app.staticTexts["home.greeting"].waitForExistence(timeout: 60)
        app.buttons["home.list.SAT RW Vocab"].waitTap(timeout: 30)
        app.buttons["wordList.study"].waitTap(timeout: 30)
        app.buttons["study.plan.Mix"].waitTap(timeout: 30)
        let found = waitForGradeRow(app, timeout: 60)
        snap("21-study-3buttons__light")
        XCTAssertTrue(found)
    }

    private func walkthrough(_ app: XCUIApplication, theme: String, full: Bool) {
        // Home
        XCTAssertTrue(app.staticTexts["home.greeting"].waitForExistence(timeout: 15))
        snap("01-home__\(theme)")

        // SAT list (frequency sort default)
        app.buttons["home.list.SAT RW Vocab"].waitTap()
        XCTAssertTrue(app.otherElements["wordList.sortChips"].waitForExistence(timeout: 25)
            || app.collectionViews.firstMatch.waitForExistence(timeout: 25))
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

        // Word detail: "some". The header-card identifier is flattened by
        // accessibility grouping, so wait on the dictionary tab bar instead.
        app.staticTexts["some"].firstMatch.waitTap()
        XCTAssertTrue(app.segmentedControls["word.tabs"].waitForExistence(timeout: 25)
            || app.staticTexts["/sʌm/"].waitForExistence(timeout: 5))
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
                tabs.buttons["English"].tap()
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
        XCTAssertTrue(app.otherElements["study.start"].waitForExistence(timeout: 25)
            || app.staticTexts["Start with:"].waitForExistence(timeout: 25))
        snap("10-study-start__\(theme)")

        // Flashcard
        app.buttons["study.plan.Mix"].waitTap()
        XCTAssertTrue(app.staticTexts["New Word"].waitForExistence(timeout: 25)
            || app.staticTexts["Review"].waitForExistence(timeout: 25))
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

        // Back home, All Words aggregate page (snap name kept for CI diffing)
        app.navigationBars.buttons.firstMatch.waitTap()
        if full {
            app.buttons["home.myWords"].waitTap()
            sleep(1)
            snap("14-mywords-empty__\(theme)")
            app.navigationBars.buttons.firstMatch.waitTap()
        }

        // Settings
        app.buttons["home.settings"].waitTap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 25))
        snap("15-settings__\(theme)")

        if full {
            // Algorithm comparison: two-layer table + expanded detail.
            app.buttons["settings.algPreview"].waitTap()
            sleep(1)
            snap("19-alg-preview__\(theme)")
            app.buttons["algPreview.row.fsrs7"].waitTap()
            sleep(1)
            snap("20-alg-preview-expanded__\(theme)")
            app.navigationBars.buttons.firstMatch.waitTap()

            app.navigationBars.buttons.firstMatch.waitTap()

            // Import words page, reached from the home word-lists tiles
            app.buttons["home.import"].waitTap()
            sleep(1)
            snap("16-import__\(theme)")
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
