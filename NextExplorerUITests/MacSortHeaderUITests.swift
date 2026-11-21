#if os(macOS)
    import CoreModels
    import Localization
    import XCTest

    final class MacSortHeaderUITests: MacUITestCase {
        private enum Constants {
            static let large = UITestFixture.File.beach.name
            static let small = UITestFixture.File.logo.name
        }

        private func isAbove(_ upper: String, _ lower: String, in app: XCUIApplication) -> Bool {
            text(upper, in: app).frame.minY < text(lower, in: app).frame.minY
        }

        func testHeadersSortTheFolderAndClickingAgainReversesIt() {
            let app = launchApp()
            openDocuments(in: app)
            XCTAssertTrue(text(Constants.small, in: app).waitToAppear())
            XCTAssertTrue(isAbove(Constants.large, Constants.small, in: app), "A folder opens sorted by name")

            let size = app.buttons[L10n.Sort.size]
            XCTAssertTrue(size.waitToAppear(), "The table should have a Size header")
            size.click()
            XCTAssertTrue(isAbove(Constants.small, Constants.large, in: app), "Size sorts smallest first")

            size.click()
            XCTAssertTrue(isAbove(Constants.large, Constants.small, in: app), "A second click sorts largest first")

            app.buttons[L10n.Sort.name].click()
            XCTAssertTrue(isAbove(Constants.large, Constants.small, in: app), "Name sorts by name again")
        }
    }
#endif
