import XCTest

/// Critical path: the row context menu and its actions (rename, share, delete), driven against
/// the mocked files client.
final class FileActionsUITests: UITestCase {
    func testContextMenuExposesActions() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
        openMenu({ browse.row(Fixture.file).longPress() }, until: browse.renameAction)

        XCTAssertTrue(browse.renameAction.exists, "The context menu should offer Rename")
        XCTAssertTrue(browse.shareAction.exists, "The context menu should offer Create share link")
        XCTAssertTrue(browse.deleteAction.exists, "The context menu should offer Delete")
    }

    func testRenameOpensSheet() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
        openMenu({ browse.row(Fixture.file).longPress() }, until: browse.renameAction)

        browse.renameAction.tap()
        XCTAssertTrue(browse.renameNameField.waitToAppear(), "Rename should present a name field")
    }

    func testDeleteShowsConfirmation() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
        openMenu({ browse.row(Fixture.file).longPress() }, until: browse.deleteAction)

        browse.deleteAction.tap()
        XCTAssertTrue(browse.deleteConfirmButton.waitToAppear(), "Delete should present a confirmation sheet")
    }

    func testRenameCompletesAndDismisses() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
        openMenu({ browse.row(Fixture.file).longPress() }, until: browse.renameAction)

        browse.renameAction.tap()
        XCTAssertTrue(browse.renameNameField.waitToAppear())
        browse.renameNameField.clearAndType("renamed.txt")
        browse.renameConfirm.tap()

        // The mocked rename succeeds, so the sheet dismisses; the field going away is the signal.
        XCTAssertTrue(browse.renameNameField.waitToVanish(), "A successful rename should dismiss the sheet")
    }

    func testDeleteCompletesAndDismisses() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
        openMenu({ browse.row(Fixture.file).longPress() }, until: browse.deleteAction)

        browse.deleteAction.tap()
        XCTAssertTrue(browse.deleteConfirmButton.waitToAppear())
        browse.deleteConfirmButton.tap()

        // The mocked delete succeeds and the confirmation sheet dismisses.
        XCTAssertTrue(browse.deleteConfirmButton.waitToVanish(), "Confirming delete should dismiss the sheet")
    }

    func testCreateShareLinkSheetOpens() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
        openMenu({ browse.row(Fixture.file).longPress() }, until: browse.shareAction)

        browse.shareAction.tap()
        XCTAssertTrue(browse.createShareSubmit.waitToAppear(), "Share should present the create link sheet")
    }

    func testDeleteRemovesRow() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
        openMenu({ browse.row(Fixture.file).longPress() }, until: browse.deleteAction)

        browse.deleteAction.tap()
        XCTAssertTrue(browse.deleteConfirmButton.waitToAppear())
        browse.deleteConfirmButton.tap()

        // The stateful mock drops the item, so the refreshed listing no longer shows it.
        XCTAssertTrue(browse.item(Fixture.file).waitToVanish(), "A confirmed delete should remove the row")
    }

    func testCompressCreatesZip() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
        openMenu({ browse.row(Fixture.file).longPress() }, until: browse.compressAction)

        browse.compressAction.tap()

        // Compress adds "<name>.zip"; the auto refreshed listing surfaces it.
        XCTAssertTrue(browse.item("\(Fixture.file).zip").waitToAppear(), "Compressing should add a .zip to the listing")
    }

    func testToggleFavoriteUpdatesContextMenu() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        // Only folders can be favorited; Photos is not a favorite in the fixture.
        XCTAssertTrue(browse.item(Fixture.folderAlt).waitToAppear())
        openMenu({ browse.row(Fixture.folderAlt).longPress() }, until: browse.addToFavoritesAction)

        browse.addToFavoritesAction.tap()

        // Reopening the menu should now offer Remove, proving the toggle took effect.
        openMenu({ browse.row(Fixture.folderAlt).longPress() }, until: browse.removeFromFavoritesAction)
        XCTAssertTrue(browse.removeFromFavoritesAction.exists, "Favoriting should flip the menu to Remove")
    }
}
