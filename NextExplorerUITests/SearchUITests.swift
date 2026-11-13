#if os(iOS)
    import CoreModels
    import Localization
    import XCTest

    /// Critical path: searching the current scope. Results come from the mocked search endpoint,
    /// which returns stable hits for any non empty query.
    final class SearchUITests: UITestCase {
        func testSearchNoMatchesShowsEmptyState() {
            let app = launchApp(auth: .loggedIn, scenario: .empty)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(TabBar(app: app).browse.waitToAppear())

            XCTAssertTrue(browse.searchField.waitToAppear())
            browse.searchField.clearAndType(Fixture.searchQuery)

            // The empty scenario's search returns nothing, so no result row should appear.
            XCTAssertFalse(
                browse.item(Fixture.searchHit).appears(within: UITestTimeout.short),
                "An empty search should not show results"
            )
        }

        func testClearSearchReturnsToListing() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.folder).waitToAppear())

            XCTAssertTrue(browse.searchField.waitToAppear())
            browse.searchField.clearAndType(Fixture.searchQuery)
            XCTAssertTrue(browse.item(Fixture.searchHit).waitToAppear())

            // Clearing the query should restore the directory listing, not leave the results up.
            browse.searchField.clearAndType("")
            XCTAssertTrue(browse.item(Fixture.folder).waitToAppear(), "Clearing search should return to the listing")
            XCTAssertFalse(
                browse.item(Fixture.searchHit).appears(within: UITestTimeout.short),
                "Cleared search should drop the results"
            )
        }

        private func visibleSearchField(_ app: XCUIApplication) -> XCUIElement {
            let fields = app.textFields.matching(identifier: AccessibilityIdentifiers.Search.field)
            return fields.allElementsBoundByIndex.first { $0.isHittable } ?? fields.firstMatch
        }

        private func openDocumentsFolder(_ app: XCUIApplication) -> BrowseScreen {
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.folder).waitToAppear())
            // Pushing can drop the first tap, so retry until the breadcrumb (shown only below the
            // root) proves the push landed.
            openMenu({ browse.item(Fixture.folder).tap() }, until: browse.breadcrumbRoot)
            return browse
        }

        func testRootSearchesEverywhereWithoutScopeChoiceOrWidening() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.folder).waitToAppear())

            XCTAssertTrue(browse.searchField.waitToAppear())
            browse.searchField.clearAndType(Fixture.searchQuery)

            XCTAssertTrue(browse.item(Fixture.widerSearchHit).waitToAppear(), "The root searches from the top")
            XCTAssertFalse(app.buttons[L10n.Browse.scopeEverywhere].exists, "There is no scope choice to make")
            XCTAssertFalse(app.buttons[L10n.Browse.scopeThisFolder].exists, "There is no scope choice to make")
            XCTAssertFalse(app.buttons[L10n.Browse.searchEverywhere].exists, "The root cannot be widened")
        }

        func testFolderSearchStaysInTheFolderUntilWidened() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = openDocumentsFolder(app)

            let field = visibleSearchField(app)
            XCTAssertTrue(field.waitToAppear())
            field.clearAndType(Fixture.searchQuery)

            XCTAssertTrue(browse.item(Fixture.searchHit).waitToAppear())
            XCTAssertFalse(
                browse.item(Fixture.widerSearchHit).exists,
                "A folder search does not look outside the folder"
            )
            XCTAssertFalse(app.buttons[L10n.Browse.scopeEverywhere].exists, "There is no scope control in a folder")

            let widen = app.buttons[L10n.Browse.searchEverywhere].firstMatch
            XCTAssertTrue(widen.waitToAppear(), "A folder search offers to search everywhere")
            widen.tap()

            XCTAssertTrue(browse.item(Fixture.widerSearchHit).waitToAppear(), "Widening searches from the root")
            XCTAssertTrue(widen.waitToVanish(), "A widened search has nothing wider to offer")
        }

        func testClearingAWidenedSearchReturnsToTheFolderScope() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = openDocumentsFolder(app)

            let field = visibleSearchField(app)
            XCTAssertTrue(field.waitToAppear())
            field.clearAndType(Fixture.searchQuery)
            let widen = app.buttons[L10n.Browse.searchEverywhere].firstMatch
            XCTAssertTrue(widen.waitToAppear())
            widen.tap()
            XCTAssertTrue(browse.item(Fixture.widerSearchHit).waitToAppear())

            field.clearAndType("")
            field.clearAndType(Fixture.searchQuery)

            XCTAssertTrue(browse.item(Fixture.searchHit).waitToAppear())
            XCTAssertTrue(
                browse.item(Fixture.widerSearchHit).waitToVanish(),
                "A new search starts inside the folder again"
            )
            XCTAssertTrue(
                app.buttons[L10n.Browse.searchEverywhere].firstMatch.waitToAppear(),
                "Widening is on offer again"
            )
        }

        func testImageFilterChipNarrowsResults() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(TabBar(app: app).browse.waitToAppear())

            XCTAssertTrue(browse.searchField.waitToAppear())
            browse.searchField.clearAndType(Fixture.searchQuery)

            // Both a document and an image hit come back before filtering.
            XCTAssertTrue(browse.item(Fixture.searchHit).waitToAppear())
            XCTAssertTrue(browse.item(Fixture.imageSearchHit).waitToAppear())

            // Selecting the Images chip should hide the document hit and keep the image.
            let imagesChip = browse.filterChip(L10n.Filter.images)
            XCTAssertTrue(imagesChip.waitToAppear(), "An image result should surface an Images filter chip")
            imagesChip.tap()

            XCTAssertTrue(
                browse.item(Fixture.searchHit).waitToVanish(),
                "Filtering to Images should hide the document hit"
            )
            XCTAssertTrue(browse.item(Fixture.imageSearchHit).exists, "Filtering to Images should keep the image hit")
        }
    }
#endif
