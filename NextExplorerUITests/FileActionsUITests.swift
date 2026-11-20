#if os(iOS)
    import XCTest

    /// Critical path: the row context menu and its actions (rename, share, delete), driven against
    /// the mocked files client.
    final class FileActionsUITests: UITestCase {
        /// One launch through the row menus: favoriting flips the folder's menu to Remove, Compress
        /// adds a zip, Delete removes it, Rename completes, and Share opens the create link sheet.
        func testRowMenuActionsTakeEffect() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            let zip = "\(Fixture.file).zip"

            // Only folders can be favorited; Photos is not a favorite in the fixture.
            XCTAssertTrue(browse.item(Fixture.folderAlt).waitToAppear())
            openMenu({ browse.row(Fixture.folderAlt).longPress() }, until: browse.addToFavoritesAction)
            browse.addToFavoritesAction.tap()
            openMenu({ browse.row(Fixture.folderAlt).longPress() }, until: browse.removeFromFavoritesAction)
            XCTAssertTrue(browse.removeFromFavoritesAction.exists, "Favoriting should flip the menu to Remove")
            browse.removeFromFavoritesAction.tap()
            XCTAssertTrue(browse.removeFromFavoritesAction.waitToVanish())

            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.compressAction)
            browse.compressAction.tap()
            XCTAssertTrue(browse.item(zip).waitToAppear(), "Compressing should add a .zip to the listing")

            openMenu({ browse.row(zip).longPress() }, until: browse.deleteAction)
            browse.deleteAction.tap()
            XCTAssertTrue(browse.deleteConfirmButton.waitToAppear())
            browse.deleteConfirmButton.tap()
            // The stateful mock drops the item, so the refreshed listing no longer shows it.
            XCTAssertTrue(browse.item(zip).waitToVanish(), "A confirmed delete should remove the row")

            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.renameAction)
            browse.renameAction.tap()
            XCTAssertTrue(browse.renameNameField.waitToAppear())
            browse.renameNameField.clearAndType("renamed.txt")
            browse.renameConfirm.tap()
            // The mocked rename succeeds, so the sheet dismisses; the field going away is the signal.
            XCTAssertTrue(browse.renameNameField.waitToVanish(), "A successful rename should dismiss the sheet")

            XCTAssertTrue(browse.item(Fixture.imageFile).waitToAppear())
            openMenu({ browse.row(Fixture.imageFile).longPress() }, until: browse.shareAction)
            browse.shareAction.tap()
            XCTAssertTrue(browse.createShareSubmit.waitToAppear(), "Share should present the create link sheet")
        }
    }
#endif
