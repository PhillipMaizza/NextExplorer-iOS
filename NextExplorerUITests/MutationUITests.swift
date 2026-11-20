#if os(iOS)
    import XCTest

    /// Critical path: a write action. Creating a folder from the browse toolbar, driven against the
    /// mocked createFolder endpoint. The new folder sheet stays open on failure and dismisses on
    /// success, so the field disappearing is the success signal.
    final class MutationUITests: UITestCase {
        /// One New Folder sheet: a name with a separator is refused inline, a name the server rejects
        /// keeps the sheet open, and a good name closes it and lists the folder.
        func testNewFolderRefusesBadNamesAndCreatesAGoodOne() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.folder).waitToAppear())
            // New Folder only appears below root; pushing can drop the first tap, so retry until the
            // folder's navigation bar proves the push landed.
            openMenu({ browse.item(Fixture.folder).tap() }, until: browse.folderNavigationBar(Fixture.folder))
            openMenu({ browse.uploadMenu.tap() }, until: browse.newFolderMenuItem)
            browse.newFolderMenuItem.tap()
            XCTAssertTrue(browse.newFolderNameField.waitToAppear())

            browse.newFolderNameField.clearAndType("a/b")
            XCTAssertTrue(browse.separatorNameError.waitToAppear(), "A name with / should show the separator error")
            XCTAssertTrue(browse.newFolderNameField.exists, "An invalid name should keep the sheet open")

            browse.newFolderNameField.clearAndType(Fixture.failingFolderName)
            browse.newFolderConfirm.tap()
            XCTAssertFalse(
                browse.newFolderNameField.waitToVanish(UITestTimeout.short),
                "A failed create should keep the sheet open"
            )

            browse.newFolderNameField.clearAndType("Reports")
            browse.newFolderConfirm.tap()
            // The stateful mock adds the folder, so the refreshed listing shows it.
            XCTAssertTrue(browse.item("Reports").waitToAppear(), "A created folder should appear in the listing")
        }
    }
#endif
