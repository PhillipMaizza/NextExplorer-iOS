import XCTest

/// Critical path: the Downloads tab. Downloads live on local disk, which is empty on a fresh
/// simulator, so the tab renders its empty state.
final class DownloadsUITests: UITestCase {
    func testDownloadsEmptyState() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let downloads = DownloadsScreen(app: app)
        selectTab(TabBar(app: app).downloads, until: downloads.emptyMessage)
        XCTAssertTrue(downloads.emptyMessage.exists, "With no local downloads the tab should show its empty state")
    }
}
