#if os(iOS)
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
            XCTAssertTrue(
                app.staticTexts[L10n.Trash.emptyState].waitToAppear(),
                "The restored file should leave the trash"
            )

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
    }
#endif
