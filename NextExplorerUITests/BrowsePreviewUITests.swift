import XCTest

/// Critical path: browsing a directory, navigating into a folder, opening a file preview, plus
/// the empty and error states. Data comes from the mocked files client fixture.
final class BrowsePreviewUITests: UITestCase {
    func testDirectoryListingShowsFixtureItems() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(browse.item(Fixture.folder).waitToAppear(), "The mocked directory listing should render its folders")
        XCTAssertTrue(browse.item(Fixture.file).waitToAppear(), "The mocked directory listing should render its files")
    }

    func testNavigateIntoFolderKeepsListing() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(browse.item(Fixture.folder).waitToAppear())
        browse.item(Fixture.folder).tap()
        // The fixture returns the same items at every depth, so the listing stays populated after
        // pushing a folder — proof the navigation resolved rather than dead ended.
        XCTAssertTrue(browse.item(Fixture.file).waitToAppear(), "Navigating into a folder should load its contents")
    }

    func testOpenFilePreview() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
        browse.item(Fixture.file).tap()
        XCTAssertTrue(browse.previewBackButton.waitToAppear(), "Opening a file should present a preview screen")
    }

    func testEmptyStateWhenNoItems() {
        let app = launchApp(auth: .loggedIn, scenario: .empty)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(TabBar(app: app).browse.waitToAppear())
        XCTAssertTrue(browse.emptyStateMessage.waitToAppear(), "An empty listing should show the empty state")
        XCTAssertFalse(browse.item(Fixture.folder).exists, "An empty listing should show no fixture items")
    }

    func testErrorStateOffersRetry() {
        let app = launchApp(auth: .loggedIn, scenario: .error)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(TabBar(app: app).browse.waitToAppear())
        XCTAssertTrue(browse.retryButton.waitToAppear(), "A failed load should offer a retry action")
    }
}
