#if os(iOS)
    import Localization
    import XCTest

    /// Opening the app with no connection at all: the signed in account stays in, Browse shows the
    /// listing saved earlier, and what was kept offline lists, opens and is found by search.
    final class OfflineLaunchUITests: UITestCase {
        /// The saved listing shows instead of login, search finds the pinned file on the device, the
        /// listing says it is a saved copy, and the Offline tab opens the kept file.
        func testTheAppOpensWithoutAConnectionAndKeptFilesStillWork() {
            let app = launchApp(offlineLaunch: true)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.folder).waitToAppear(), "The saved listing shows, not the login")

            browse.searchField.clearAndType(Fixture.fileSearchTerm)
            XCTAssertTrue(browse.sectionHeader(L10n.Search.onDevice).waitToAppear(), "Found, as on the device")
            XCTAssertTrue(browse.item(Fixture.file).exists)
            browse.searchField.clearAndType("")
            XCTAssertTrue(browse.item(Fixture.folder).waitToAppear())

            // The note is the listing's last row, below the fold of a full root.
            XCTAssertTrue(scrollTo(savedCopyNote(in: app), in: app), "It says the listing is a saved copy")

            let offline = OfflineTabScreen(app: app)
            selectTab(TabBar(app: app).downloads, until: offline.row(Fixture.file))
            offline.row(Fixture.file).tap()
            XCTAssertTrue(browse.previewBackButton.waitToAppear(), "The kept copy opens offline")
        }
    }
#endif
