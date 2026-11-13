#if os(macOS)
    import Localization
    import XCTest

    /// The Mac search table with files kept offline: "On device" rows first, then "Remote", and
    /// without a connection what was kept is still found.
    final class MacOfflineSearchUITests: MacUITestCase {
        private func search(in app: XCUIApplication) {
            app.typeKey(Constants.findKey, modifierFlags: .command)
            app.typeText(Fixture.fileSearchTerm)
        }

        func testThePinnedFileHeadsTheSearchTableUnderOnDevice() {
            let app = launchApp()
            pinForOffline(Fixture.file, in: app)

            search(in: app)

            XCTAssertTrue(text(L10n.Search.onDevice, in: app).waitToAppear(), "Kept files get their own heading")
            XCTAssertTrue(text(L10n.Search.remote, in: app).exists, "The others are under Remote")
            XCTAssertTrue(searchHit(in: app).waitToAppear(), "Server hits are listed too")
        }

        func testWithNothingKeptThereAreNoHeadings() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.file, in: app).waitToAppear())

            search(in: app)

            XCTAssertTrue(searchHit(in: app).waitToAppear())
            XCTAssertFalse(text(L10n.Search.onDevice, in: app).exists, "One plain table when nothing is kept")
        }

        func testOfflineThePinnedFileIsStillFound() {
            let app = launchApp(searchOffline: true)
            pinForOffline(Fixture.file, in: app)

            search(in: app)

            XCTAssertTrue(
                text(L10n.Search.onDevice, in: app).waitToAppear(),
                "Without a connection the kept file is still found, as on the device"
            )
            XCTAssertFalse(searchHit(in: app).exists, "Nothing the server alone knows is invented")
        }
    }
#endif
