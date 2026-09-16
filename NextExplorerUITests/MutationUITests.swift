import XCTest

/// Critical path: a write action. Creating a folder from the browse toolbar, driven against the
/// mocked createFolder endpoint. The new folder sheet stays open on failure and dismisses on
/// success, so the field disappearing is the success signal.
final class MutationUITests: UITestCase {
    func testCreateFolder() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)

        // New Folder only appears below the root, so push into a folder first.
        XCTAssertTrue(browse.item(Fixture.folder).waitToAppear())
        browse.item(Fixture.folder).tap()

        XCTAssertTrue(browse.uploadMenu.waitToAppear(), "The upload/new folder menu should be in the toolbar inside a folder")
        openMenu({ browse.uploadMenu.tap() }, until: browse.newFolderMenuItem)
        browse.newFolderMenuItem.tap()

        XCTAssertTrue(browse.newFolderNameField.waitToAppear(), "The new folder sheet should present a name field")
        browse.newFolderNameField.clearAndType("Reports")

        browse.newFolderConfirm.tap()

        // On success the sheet dismisses; the name field goes away.
        XCTAssertTrue(browse.newFolderNameField.waitToVanish(), "A successful create should dismiss the sheet")
    }

    func testNewFolderCreatedAppearsInListing() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(browse.item(Fixture.folder).waitToAppear())
        // New Folder only appears below root; pushing can drop the first tap, so retry until the
        // upload menu (folder only toolbar item) shows.
        openMenu({ browse.item(Fixture.folder).tap() }, until: browse.uploadMenu)
        openMenu({ browse.uploadMenu.tap() }, until: browse.newFolderMenuItem)
        browse.newFolderMenuItem.tap()

        XCTAssertTrue(browse.newFolderNameField.waitToAppear())
        browse.newFolderNameField.clearAndType("Reports")
        browse.newFolderConfirm.tap()

        // The stateful mock adds the folder, so the refreshed listing shows it.
        XCTAssertTrue(browse.item("Reports").waitToAppear(), "A created folder should appear in the listing")
    }

    func testNewFolderInvalidNameShowsError() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(browse.item(Fixture.folder).waitToAppear())
        openMenu({ browse.item(Fixture.folder).tap() }, until: browse.uploadMenu)
        openMenu({ browse.uploadMenu.tap() }, until: browse.newFolderMenuItem)
        browse.newFolderMenuItem.tap()

        XCTAssertTrue(browse.newFolderNameField.waitToAppear())
        browse.newFolderNameField.clearAndType("a/b")

        // A name with a separator is rejected inline and the sheet stays open.
        XCTAssertTrue(browse.separatorNameError.waitToAppear(), "A name with / should show the separator error")
        XCTAssertTrue(browse.newFolderNameField.exists, "An invalid name should keep the sheet open")
    }

    func testCreateFolderServerFailureKeepsSheetOpen() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(browse.item(Fixture.folder).waitToAppear())
        openMenu({ browse.item(Fixture.folder).tap() }, until: browse.uploadMenu)
        openMenu({ browse.uploadMenu.tap() }, until: browse.newFolderMenuItem)
        browse.newFolderMenuItem.tap()

        XCTAssertTrue(browse.newFolderNameField.waitToAppear())
        browse.newFolderNameField.clearAndType(Fixture.failingFolderName)
        browse.newFolderConfirm.tap()

        // The mocked backend rejects this name; the sheet must stay open rather than dismiss.
        XCTAssertFalse(browse.newFolderNameField.waitToVanish(UITestTimeout.short), "A failed create should keep the sheet open")
    }
}
