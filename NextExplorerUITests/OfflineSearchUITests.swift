#if os(iOS)
    import Localization
    import XCTest

    /// Search with files kept offline: what is on the device heads the results under "On device",
    /// the rest follow under "Remote", in the list and in the grid, and without a connection what was
    /// kept is still found.
    final class OfflineSearchUITests: UITestCase {
        private func pinFile(_ browse: BrowseScreen) {
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.availableOfflineAction)
            browse.availableOfflineAction.tap()
        }

        private func search(_ browse: BrowseScreen) {
            XCTAssertTrue(browse.searchField.waitToAppear())
            browse.searchField.clearAndType(Fixture.fileSearchTerm)
        }

        func testAPinnedFileHeadsTheResultsUnderOnDeviceAndTheRestAreRemote() {
            let app = launchApp()
            let browse = BrowseScreen(app: app)
            pinFile(browse)

            search(browse)

            XCTAssertTrue(browse.sectionHeader(L10n.Search.onDevice).waitToAppear(), "Kept files get their own heading")
            XCTAssertTrue(browse.sectionHeader(L10n.Search.remote).exists, "The others are under Remote")
            XCTAssertTrue(browse.item(Fixture.file).exists, "The pinned file is listed")
            XCTAssertTrue(browse.item(Fixture.searchHit).waitToAppear(), "Server hits are listed too")
            XCTAssertLessThan(
                browse.item(Fixture.file).frame.minY,
                browse.item(Fixture.searchHit).frame.minY,
                "What is on the device comes first"
            )
        }

        func testTheGridSplitsTheResultsTheSameWay() {
            let app = launchApp()
            let browse = BrowseScreen(app: app)
            pinFile(browse)
            openMenu({ browse.moreMenu.tap() }, until: browse.gridViewToggle)
            browse.gridViewToggle.tap()

            search(browse)

            XCTAssertTrue(browse.sectionHeader(L10n.Search.onDevice).waitToAppear(), "The grid has the heading too")
            XCTAssertTrue(browse.sectionHeader(L10n.Search.remote).exists)
            XCTAssertTrue(browse.item(Fixture.searchHit).waitToAppear())
        }

        func testWithNothingKeptThereAreNoHeadings() {
            let app = launchApp()
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())

            search(browse)

            XCTAssertTrue(browse.item(Fixture.searchHit).waitToAppear())
            XCTAssertFalse(browse.sectionHeader(L10n.Search.onDevice).exists, "One plain list when nothing is kept")
            XCTAssertFalse(browse.sectionHeader(L10n.Search.remote).exists)
        }

        func testOfflineAPinnedFileIsStillFoundUnderOnDevice() {
            let app = launchApp(searchOffline: true)
            let browse = BrowseScreen(app: app)
            pinFile(browse)

            search(browse)

            XCTAssertTrue(
                browse.sectionHeader(L10n.Search.onDevice).waitToAppear(),
                "Without a connection the kept file is still found, as on the device"
            )
            XCTAssertTrue(browse.item(Fixture.file).exists)
            XCTAssertFalse(browse.item(Fixture.searchHit).exists, "Nothing the server alone knows is invented")
        }

        func testOfflineAPinnedFileFoundBySearchOpens() {
            let app = launchApp(searchOffline: true)
            let browse = BrowseScreen(app: app)
            pinFile(browse)
            search(browse)
            XCTAssertTrue(browse.sectionHeader(L10n.Search.onDevice).waitToAppear())

            browse.item(Fixture.file).tap()

            XCTAssertTrue(browse.previewBackButton.waitToAppear(), "The kept file opens from the results")
        }
    }
#endif
