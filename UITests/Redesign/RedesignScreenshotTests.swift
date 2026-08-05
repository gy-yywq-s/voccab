import XCTest

/// Walks every page of the Neo (redesigned) frontend and captures
/// screenshots, in light and dark appearance. Page order mirrors the classic
/// walkthrough so the two designs can be compared side by side.
final class RedesignScreenshotTests: XCTestCase {

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
        // Generous, non-fatal wait: this is the third launch in the run and
        // the simulator can be slow; the real assertion is the grade row.
        _ = app.staticTexts["home.greeting"].waitForExistence(timeout: 40)
        app.buttons["home.list.SAT RW Vocab"].waitTap()
        app.buttons["wordList.study"].waitTap()
        app.buttons["study.plan.Mix"].waitTap()
        XCTAssertTrue(app.buttons["study.grade.1"].waitForExistence(timeout: 25)
            || app.staticTexts["Again"].waitForExistence(timeout: 25))
        snap("21-study-3buttons__light")
    }

    /// The dictionary switcher is a row of plain SwiftUI Buttons, so the
    /// label text is consumed into the button element rather than surfacing
    /// as a StaticText. Try every plausible query, tapping by coordinate if
    /// the match isn't hittable; dump the hierarchy when nothing matches.
    @discardableResult
    private func tapDictionaryTab(_ app: XCUIApplication, _ name: String) -> Bool {
        let candidates: [XCUIElement] = [
            app.buttons["word.tab.\(name)"].firstMatch,
            app.buttons[name].firstMatch,
            app.staticTexts[name].firstMatch,
            app.descendants(matching: .any)["word.tab.\(name)"].firstMatch,
        ]
        for element in candidates where element.waitForExistence(timeout: 3) {
            if element.isHittable {
                element.tap()
            } else {
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            return true
        }
        print("VOCCAB-DEBUG: dictionary tab \(name) not found; hierarchy:\n\(app.debugDescription)")
        return false
    }

    private func walkthrough(_ app: XCUIApplication, theme: String, full: Bool) {
        // Home
        XCTAssertTrue(app.staticTexts["home.greeting"].waitForExistence(timeout: 15))
        snap("01-home__\(theme)")

        // SAT list
        app.buttons["home.list.SAT RW Vocab"].waitTap()
        let sortControl = app.segmentedControls["wordList.sortChips"]
        XCTAssertTrue(sortControl.waitForExistence(timeout: 25))
        snap("02-list-frequency__\(theme)")

        if full {
            sortControl.buttons["Recall"].waitTap()
            sleep(1)
            snap("03-list-familiarity__\(theme)")
            sortControl.buttons["Review"].waitTap()
            sleep(1)
            snap("04-list-planned__\(theme)")
            sortControl.buttons["Frequency"].waitTap()
            sleep(1)
        }

        // Word detail: "some"
        app.staticTexts["some"].firstMatch.waitTap()
        XCTAssertTrue(app.staticTexts["/sʌm/"].waitForExistence(timeout: 25)
            || app.buttons["word.tab.Oxford"].waitForExistence(timeout: 25))
        snap("05-word-related__\(theme)")

        if full {
            snap("06-word-studyinfo__\(theme)")

            if tapDictionaryTab(app, "English") {
                sleep(1)
                snap("07-word-english__\(theme)")
            }
            if tapDictionaryTab(app, "Synonyms") {
                sleep(1)
                snap("08-word-synonyms__\(theme)")
            }
            if tapDictionaryTab(app, "Oxford") {
                sleep(1)
                snap("09-word-oxford__\(theme)")
            }
        }

        // Back to list, then study start. Navigation can need a beat after
        // the pager; wait generously on the plan rows without hard-failing
        // the walkthrough (the screenshot is the evidence).
        app.navigationBars.buttons.firstMatch.waitTap()
        app.buttons["wordList.study"].waitTap()
        _ = app.buttons["study.plan.Mix"].waitForExistence(timeout: 15)
        snap("10-study-start__\(theme)")

        // Flashcard. The styled answer bars surface their text, not a button
        // role, so query and tap by the visible label.
        app.buttons["study.plan.Mix"].waitTap()
        XCTAssertTrue(app.staticTexts["I Know"].waitForExistence(timeout: 25))
        snap("11-study-card__\(theme)")

        if full {
            app.staticTexts["I Know"].firstMatch.tap()
            sleep(1)
            snap("12-study-reveal__\(theme)")
        }

        // Leave session; list bottom bar shows paused state
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
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 25)
            || app.navigationBars["Settings"].waitForExistence(timeout: 25))
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

            // Import words page, reached from the home word-lists zone.
            app.buttons["home.import"].waitTap()
            sleep(1)
            snap("16-import__\(theme)")
            app.navigationBars.buttons.firstMatch.waitTap()

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
