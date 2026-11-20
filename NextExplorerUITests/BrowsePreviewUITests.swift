#if os(iOS)
    import XCTest

    /// Critical path: the Browse area's empty and error states. Opening files and folders is in
    /// `BrowseWorldUITests`.
    final class BrowsePreviewUITests: UITestCase {
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
#endif
