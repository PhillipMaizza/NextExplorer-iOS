import XCTest

/// Critical path: the Browse toolbar's list/grid view toggle. Driven against the mocked files
/// client.
///
/// Sort and pull to refresh are deliberately not covered here: the sort control resolves as a
/// system PopUpButton that XCUITest can't tap by label, and pull to refresh depends on a drag
/// gesture that trips the refresh control only intermittently. Both would be flaky, not durable.
final class BrowseToolbarUITests: UITestCase {
    func testGridViewToggleKeepsItems() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(browse.item(Fixture.folder).waitToAppear())

        openMenu({ browse.moreMenu.tap() }, until: browse.gridViewToggle)
        browse.gridViewToggle.tap()

        // Switching to grid re-lays out the same items; they should still be on screen.
        XCTAssertTrue(browse.item(Fixture.folder).waitToAppear(), "Grid view should still render the items")
        XCTAssertTrue(browse.item(Fixture.file).exists)
    }
}
