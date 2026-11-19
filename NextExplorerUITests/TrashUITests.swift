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

        func testEmptyTrashRemovesEverything() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.deleteAction)
            browse.deleteAction.tap()
            XCTAssertTrue(browse.deleteConfirmButton.waitToAppear())
            browse.deleteConfirmButton.tap()
            XCTAssertTrue(browse.item(Fixture.file).waitToVanish())

            XCTAssertTrue(browse.trashButton.waitToAppear(), "The Browse root toolbar should offer the Trash")
            browse.trashButton.tap()
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())

            let empty = app.labeledButton(L10n.Trash.emptyTrash)
            openMenu({ app.navigationBars.buttons[L10n.Common.more].firstMatch.tap() }, until: empty)
            empty.tap()
            let confirm = app.labeledButton(L10n.Trash.emptyTrash)
            XCTAssertTrue(confirm.waitToAppear(), "Empty Trash should ask first")
            confirm.tap()
            XCTAssertTrue(app.staticTexts[L10n.Trash.emptyState].waitToAppear(), "The trash should be empty")
        }

        private typealias Entry = UITestFixture.TrashEntry

        private func openTrash(_ app: XCUIApplication) -> BrowseScreen {
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.trashButton.waitToAppear(), "The Browse root toolbar should offer the Trash")
            browse.trashButton.tap()
            return browse
        }

        func testTheSeededTrashShowsEveryRowState() {
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
        }

        func testADeletedFolderOpensToWhatItHeld() {
            let app = launchApp()
            let browse = openTrash(app)
            XCTAssertTrue(browse.item(Entry.oldPhotos.name).waitToAppear())
            let inside = browse.item(UITestFixture.TrashedPhotosEntry.shotList.name)
            openMenu({ browse.item(Entry.oldPhotos.name).tap() }, until: inside)
            for entry in UITestFixture.TrashedPhotosEntry.allCases {
                XCTAssertTrue(browse.item(entry.name).exists, "\(entry) is inside the deleted folder")
            }
        }

        func testAnEmptyTrashSaysSo() {
            let app = launchApp(empty: [.trash])
            _ = openTrash(app)
            XCTAssertTrue(app.staticTexts[L10n.Trash.emptyState].waitToAppear())
        }

        func testATrashThatFailsToLoadSaysSo() {
            let app = launchApp(failing: [.trash])
            _ = openTrash(app)
            XCTAssertTrue(app.staticTexts.showingPart(L10n.Trash.loadFailed).waitToAppear())
        }
    }
#endif
