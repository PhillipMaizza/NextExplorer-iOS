#if os(iOS)
    import XCTest

    /// Critical path: the Offline tab (formerly Downloads). Nothing is pinned and the saved downloads
    /// folder is empty on a fresh simulator, so the tab renders its empty state.
    final class DownloadsUITests: UITestCase {
        func testDownloadsEmptyState() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let downloads = OfflineTabScreen(app: app)
            selectTab(TabBar(app: app).downloads, until: downloads.emptyMessage)
            XCTAssertTrue(downloads.emptyMessage.exists, "With nothing offline the tab should show its empty state")
        }
    }
#endif
