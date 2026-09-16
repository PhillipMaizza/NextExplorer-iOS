import XCTest

/// Critical path: the Shared tab, its By me / With me segments, and their lists. Backed by the
/// mocked share endpoints.
final class SharedUITests: UITestCase {
    /// Labels the mocked share fixtures carry (Share.previewSharedByMe / previewSharedWithMe).
    private enum ShareFixture {
        static let byMe = "Electricity"
        static let withMe = "Team Roadmap"
    }

    func testSharedByMeListShowsItems() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let shared = SharedScreen(app: app)
        selectTab(TabBar(app: app).shared, until: shared.item(ShareFixture.byMe))
        XCTAssertTrue(shared.item(ShareFixture.byMe).exists, "By me should list the mocked shares")
    }

    func testSwitchToWithMeSegment() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let shared = SharedScreen(app: app)
        selectTab(TabBar(app: app).shared, until: shared.byMeSegment)

        shared.withMeSegment.tap()
        XCTAssertTrue(shared.item(ShareFixture.withMe).waitToAppear(), "With me should list shares others sent")
    }

    func testSharedEmptyState() {
        let app = launchApp(auth: .loggedIn, scenario: .empty)
        let shared = SharedScreen(app: app)
        selectTab(TabBar(app: app).shared, until: shared.emptyByMe)
        XCTAssertTrue(shared.emptyByMe.exists, "No shares should show the empty state")
    }
}
