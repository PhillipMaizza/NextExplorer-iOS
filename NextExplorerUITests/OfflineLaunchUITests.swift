#if os(iOS)
    import Localization
    import XCTest

    /// Opening the app with no connection at all: the signed in account stays in, Browse shows the
    /// listing saved earlier, and what was kept offline lists, opens and is found by search.
    final class OfflineLaunchUITests: UITestCase {
        func testTheAppOpensWithoutAConnectionOnTheSavedListing() {
            let app = launchApp(offlineLaunch: true)
            let browse = BrowseScreen(app: app)

            XCTAssertTrue(browse.item(Fixture.folder).waitToAppear(), "The saved listing shows, not the login")
            XCTAssertTrue(savedCopyNote(in: app).waitToAppear(), "It says the listing is a saved copy")
        }

        func testAPinnedFileListsAndOpensWithoutAConnection() {
            let app = launchApp(offlineLaunch: true)
            let offline = OfflineTabScreen(app: app)
            XCTAssertTrue(TabBar(app: app).downloads.waitToAppear())
            selectTab(TabBar(app: app).downloads, until: offline.row(Fixture.file))

            offline.row(Fixture.file).tap()

            XCTAssertTrue(BrowseScreen(app: app).previewBackButton.waitToAppear(), "The kept copy opens offline")
        }

        func testSearchWithoutAConnectionFindsThePinnedFileOnTheDevice() {
            let app = launchApp(offlineLaunch: true)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.folder).waitToAppear())

            browse.searchField.clearAndType(Fixture.fileSearchTerm)

            XCTAssertTrue(browse.sectionHeader(L10n.Search.onDevice).waitToAppear(), "Found, as on the device")
            XCTAssertTrue(browse.item(Fixture.file).exists)
        }
    }
#endif
