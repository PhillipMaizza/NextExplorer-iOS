#if os(macOS)
    import Localization
    import XCTest

    /// Opening the Mac app with no connection at all: the saved listing shows, and what was kept
    /// offline lists, opens and is found by search.
    final class MacOfflineLaunchUITests: MacUITestCase {
        func testTheAppOpensWithoutAConnectionOnTheSavedListing() {
            let app = launchApp(offlineLaunch: true)

            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear(), "The saved listing shows, not the login")
            XCTAssertTrue(savedCopyNote(in: app).waitToAppear(), "It says it is a saved copy")
        }

        func testAPinnedFileListsAndOpensWithoutAConnection() {
            let app = launchApp(offlineLaunch: true)
            let item = sidebarItem(L10n.Tab.offline, in: app)
            XCTAssertTrue(item.waitToAppear())
            item.click()
            let row = text(Fixture.file, in: app)
            XCTAssertTrue(row.waitToAppear(), "The pinned file is listed offline")

            row.doubleClick()

            XCTAssertTrue(app.sheets.firstMatch.waitToAppear(), "The kept copy opens offline")
        }

        func testSearchWithoutAConnectionFindsThePinnedFileOnTheDevice() {
            let app = launchApp(offlineLaunch: true)
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())

            app.typeKey(Constants.findKey, modifierFlags: .command)
            app.typeText(Fixture.fileSearchTerm)

            XCTAssertTrue(text(L10n.Search.onDevice, in: app).waitToAppear(), "Found, as on the device")
        }
    }
#endif
