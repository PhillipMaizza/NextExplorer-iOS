import XCTest

/// Critical path: the Browse toolbar's list/grid view toggle, sort, and pull to refresh. Driven
/// against the mocked files client.
///
/// Sort resolves through a custom `SortSheet` (tappable radio rows), not a system PopUpButton, so
/// it is matchable by label. Pull to refresh uses a slow coordinate drag rather than `swipeDown`,
/// which reliably crosses the refresh threshold, and asserts on the "Sync completed" toast the
/// refresh raises rather than on the gesture itself.
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

    func testSortDescendingReordersFolders() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        // The two folder row buttons carry distinct frames; comparison is by reading order (top
        // then leading) so the assertion holds whether the persisted view mode is list or grid.
        let documents = browse.row(Fixture.folder)
        let photos = browse.row(Fixture.folderAlt)
        XCTAssertTrue(documents.waitToAppear())
        XCTAssertTrue(photos.waitToAppear())

        // Default sort is name ascending with folders first: Documents before Photos.
        XCTAssertTrue(precedesInReadingOrder(documents, photos), "Name ascending should place Documents before Photos")

        openMenu({ browse.moreMenu.tap() }, until: browse.sortMenuItem)
        browse.sortMenuItem.tap()
        XCTAssertTrue(browse.sortSheetTitle.waitToAppear(), "Sort sheet should open")
        browse.sortDescendingOption.tap()
        browse.sortSheetClose.tap()
        XCTAssertTrue(browse.sortSheetTitle.waitToVanish(), "Sort sheet should close")

        // Name descending flips the folder group: Photos now before Documents.
        XCTAssertTrue(photos.waitToAppear())
        XCTAssertTrue(precedesInReadingOrder(photos, documents), "Name descending should place Photos before Documents")
    }

    func testPullToRefreshRaisesSyncToast() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        let documents = browse.item(Fixture.folder)
        XCTAssertTrue(documents.waitToAppear())

        // A held coordinate drag downward trips the refresh control where a plain swipeDown only
        // catches it intermittently. The terminal hold (not the drag speed) is what pushes
        // `.refreshable` past its threshold, so the drag runs at `.default` velocity: `.slow` over a
        // long distance takes many seconds per attempt and, under the parallel-clone CI load, stalls
        // the whole test past its timeout. The gesture is still occasionally dropped, so retry it (as
        // the suite does for tab/menu gestures) until the "Sync completed" toast the refresh raises
        // appears.
        let toast = browse.syncCompletedToast
        var pulled = false
        for _ in 0 ..< 5 where !pulled {
            let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            let end = start.withOffset(CGVector(dx: 0, dy: 500))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.4)
            pulled = toast.appears(within: UITestTimeout.short)
        }
        XCTAssertTrue(pulled, "Pull to refresh should raise the sync completed toast")
    }

    /// Whether `a` comes before `b` in reading order: higher on screen, or same row and further
    /// leading. Keeps the sort assertion valid in both list (vertical) and grid (row major) modes.
    private func precedesInReadingOrder(_ a: XCUIElement, _ b: XCUIElement) -> Bool {
        let fa = a.frame
        let fb = b.frame
        if abs(fa.minY - fb.minY) > 1 {
            return fa.minY < fb.minY
        }
        return fa.minX < fb.minX
    }
}
