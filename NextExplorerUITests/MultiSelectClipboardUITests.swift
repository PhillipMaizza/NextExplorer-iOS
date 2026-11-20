#if os(iOS)
    import XCTest

    /// Critical path: multi select mode and the copy/paste clipboard, driven against the mocked
    /// transfer endpoint.
    final class MultiSelectClipboardUITests: UITestCase {
        /// A copied file pastes into a folder, asking first about the name it already holds; back at
        /// the root, select mode selects all and cancels out, and two picked rows offer Available
        /// Offline and delete in bulk.
        func testCopyPasteThenSelectModeDeletesInBulk() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())

            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.copyAction)
            browse.copyAction.tap()
            // Paste is only offered inside a folder, so push into one.
            openMenu({ browse.item(Fixture.folder).tap() }, until: browse.folderNavigationBar(Fixture.folder))
            openMenu({ browse.moreMenu.tap() }, until: browse.pasteMenuItem)
            browse.pasteMenuItem.tap()
            // The mocked folder already holds notes.txt, so the collision prompt comes first.
            XCTAssertTrue(browse.keepBothButton.waitToAppear(), "Pasting onto a name in use should ask first")
            browse.keepBothButton.tap()
            XCTAssertTrue(browse.keepBothButton.waitToVanish())
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())

            openMenu({ browse.moreMenu.tap() }, until: browse.selectMenuItem)
            browse.selectMenuItem.tap()
            XCTAssertTrue(browse.selectAllButton.waitToAppear(), "Select mode should expose Select All")
            browse.selectAllButton.tap()
            XCTAssertTrue(browse.cancelButton.waitToAppear(), "Select mode should expose Cancel")
            browse.cancelButton.tap()
            XCTAssertTrue(browse.selectAllButton.waitToVanish(), "Cancel should leave select mode")

            openMenu({ browse.moreMenu.tap() }, until: browse.selectMenuItem)
            browse.selectMenuItem.tap()

            // Select two rows, then delete them from the selection menu.
            XCTAssertTrue(browse.row(Fixture.file).waitToAppear())
            XCTAssertFalse(browse.selectionActionsMenu.exists, "With nothing selected the bar offers nothing")
            browse.row(Fixture.file).tap()
            browse.row(Fixture.imageFile).tap()

            openMenu({ browse.selectionActionsMenu.tap() }, until: browse.bulkDeleteButton)
            XCTAssertTrue(
                browse.offlineSelectionButton.isEnabled(within: UITestTimeout.standard),
                "A selection enables Available Offline"
            )
            browse.bulkDeleteButton.tap()

            XCTAssertTrue(browse.deleteConfirmButton.waitToAppear(), "Bulk delete should confirm first")
            browse.deleteConfirmButton.tap()

            // The stateful mock removes both; the listing drops them.
            XCTAssertTrue(browse.item(Fixture.file).waitToVanish(), "A bulk delete should remove the selected rows")
        }

        func testCancellingARunningBulkDeleteKeepsTheRows() {
            let app = launchApp(auth: .loggedIn, scenario: .slowOperations)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())

            openMenu({ browse.moreMenu.tap() }, until: browse.selectMenuItem)
            browse.selectMenuItem.tap()
            XCTAssertTrue(browse.row(Fixture.file).waitToAppear())
            browse.row(Fixture.file).tap()
            browse.row(Fixture.imageFile).tap()
            openMenu({ browse.selectionActionsMenu.tap() }, until: browse.bulkDeleteButton)
            browse.bulkDeleteButton.tap()
            XCTAssertTrue(browse.deleteConfirmButton.waitToAppear())
            browse.deleteConfirmButton.tap()

            // The pill shows after a short delay and exposes Cancel only as its trailing button.
            let pill = browse.deleteProgressPill
            XCTAssertTrue(pill.waitToAppear(), "A running delete should show its progress bar")
            pill.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()

            XCTAssertTrue(pill.waitToVanish(), "Cancel should remove the progress bar")
            XCTAssertTrue(browse.item(Fixture.file).exists, "A cancelled delete keeps the rows")
        }

        func testCancellingARunningPasteRemovesTheProgressBar() {
            let app = launchApp(auth: .loggedIn, scenario: .slowOperations)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())

            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.copyAction)
            browse.copyAction.tap()
            browse.item(Fixture.folder).tap()
            XCTAssertTrue(browse.moreMenu.waitToAppear())
            openMenu({ browse.moreMenu.tap() }, until: browse.pasteMenuItem)
            browse.pasteMenuItem.tap()

            // The mocked folder already holds notes.txt, so the collision prompt comes first.
            XCTAssertTrue(browse.keepBothButton.waitToAppear())
            browse.keepBothButton.tap()

            let pill = browse.copyProgressPill
            XCTAssertTrue(pill.waitToAppear(), "A running copy should show its progress bar")
            pill.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()

            XCTAssertTrue(pill.waitToVanish(), "Cancel should remove the progress bar")
        }
    }
#endif
