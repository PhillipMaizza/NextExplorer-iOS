#if os(iOS)
    import XCTest

    /// Critical path: multi select mode and the copy/paste clipboard, driven against the mocked
    /// transfer endpoint.
    final class MultiSelectClipboardUITests: UITestCase {
        func testEnterSelectModeAndSelectAll() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.folder).waitToAppear())

            openMenu({ browse.moreMenu.tap() }, until: browse.selectMenuItem)
            browse.selectMenuItem.tap()

            XCTAssertTrue(browse.selectAllButton.waitToAppear(), "Select mode should expose Select All")
            browse.selectAllButton.tap()

            XCTAssertTrue(browse.cancelButton.waitToAppear(), "Select mode should expose Cancel")
            browse.cancelButton.tap()
            XCTAssertTrue(browse.selectAllButton.waitToVanish(), "Cancel should leave select mode")
        }

        func testCopyThenPasteIntoFolder() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())

            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.copyAction)
            browse.copyAction.tap()

            // Paste is only offered inside a folder, so push into one.
            browse.item(Fixture.folder).tap()
            XCTAssertTrue(browse.moreMenu.waitToAppear())
            openMenu({ browse.moreMenu.tap() }, until: browse.pasteMenuItem)

            browse.pasteMenuItem.tap()
            XCTAssertTrue(browse.pasteMenuItem.waitToVanish(), "Pasting should dismiss the menu")
        }

        func testSelectMultipleThenBulkDelete() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())

            openMenu({ browse.moreMenu.tap() }, until: browse.selectMenuItem)
            browse.selectMenuItem.tap()

            // Select two rows, then delete them from the selection menu.
            XCTAssertTrue(browse.row(Fixture.file).waitToAppear())
            XCTAssertFalse(browse.selectionActionsMenu.exists, "With nothing selected the bar offers nothing")
            browse.row(Fixture.file).tap()
            browse.row(Fixture.imageFile).tap()

            openMenu({ browse.selectionActionsMenu.tap() }, until: browse.bulkDeleteButton)
            browse.bulkDeleteButton.tap()

            XCTAssertTrue(browse.deleteConfirmButton.waitToAppear(), "Bulk delete should confirm first")
            browse.deleteConfirmButton.tap()

            // The stateful mock removes both; the listing drops them.
            XCTAssertTrue(browse.item(Fixture.file).waitToVanish(), "A bulk delete should remove the selected rows")
        }
    }
#endif
