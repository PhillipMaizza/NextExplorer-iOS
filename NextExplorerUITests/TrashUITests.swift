#if os(iOS)
    import CoreModels
    import Localization
    import XCTest

    /// The trash against the mocked server: a deleted file lands there and comes back from it.
    final class TrashUITests: UITestCase {
        func testADeletedFileIsRestoredFromTheTrash() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.deleteAction)
            browse.deleteAction.tap()
            XCTAssertTrue(browse.deleteConfirmButton.waitToAppear())
            browse.deleteConfirmButton.tap()
            XCTAssertTrue(browse.item(Fixture.file).waitToVanish(), "A confirmed delete should remove the row")

            XCTAssertTrue(browse.trashButton.waitToAppear(), "The Browse root toolbar should offer the Trash")
            browse.trashButton.tap()
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear(), "The deleted file should be in the trash")

            let restore = app.labeledButton(L10n.Trash.restore)
            openMenu({ browse.row(Fixture.file).longPress() }, until: restore)
            restore.tap()
            XCTAssertTrue(browse.item(Fixture.file).waitToVanish(), "The restored file should leave the trash")

            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear(), "The restored file should be back in its folder")
        }

        private typealias Entry = UITestFixture.TrashEntry

        private func openTrash(_ app: XCUIApplication) -> BrowseScreen {
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.trashButton.waitToAppear(), "The Browse root toolbar should offer the Trash")
            browse.trashButton.tap()
            return browse
        }

        /// The seeded trash shows one row per state, a deleted folder opens to what it held, and
        /// Empty Trash asks first and then clears it all.
        func testTheSeededTrashShowsEveryStateOpensAFolderAndEmpties() {
            let app = launchApp()
            let browse = openTrash(app)
            for entry in Entry.allCases {
                XCTAssertTrue(scrollTo(browse.item(entry.name), in: app), "\(entry) is in the trash")
            }
            XCTAssertTrue(app.staticTexts.showingPart(L10n.Trash.removedToday).exists, "One item goes today")
            XCTAssertTrue(app.staticTexts.showingPart(L10n.Trash.unavailable).exists, "One sits on an unmounted volume")
            XCTAssertTrue(
                app.staticTexts.showingPart(L10n.Trash.deletedByShareLink).exists,
                "One came in through a link"
            )
            XCTAssertTrue(
                app.staticTexts.showingPart(Entry.otherPerson.displayName).exists,
                "One was deleted by someone else"
            )
            XCTAssertTrue(app.staticTexts.showingPart(L10n.Trash.sharesBadge).exists, "One had share links")

            XCTAssertTrue(scrollTo(browse.item(Entry.oldPhotos.name), in: app))
            let inside = browse.item(UITestFixture.TrashedPhotosEntry.shotList.name)
            openMenu({ browse.item(Entry.oldPhotos.name).tap() }, until: inside)
            for entry in UITestFixture.TrashedPhotosEntry.allCases {
                XCTAssertTrue(browse.item(entry.name).exists, "\(entry) is inside the deleted folder")
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()

            let empty = app.labeledButton(L10n.Trash.emptyTrash)
            openMenu({ app.navigationBars.buttons[L10n.Common.more].firstMatch.tap() }, until: empty)
            // A tap while the menu still slides in is dropped.
            empty.waitForFrameToSettle()
            empty.tap()
            // The confirm button shares the menu item's label, so wait on the sheet's own title, which
            // reads as one with its message.
            XCTAssertTrue(
                app.descendants(matching: .any).showingPart(L10n.Trash.confirmEmptyTitle).waitToAppear(),
                "Empty Trash should ask first"
            )
            app.labeledButton(L10n.Trash.emptyTrash).tap()
            XCTAssertTrue(app.staticTexts[L10n.Trash.emptyState].waitToAppear(), "The trash should be empty")
        }
    }
#endif
