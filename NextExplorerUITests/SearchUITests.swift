#if os(iOS)
    import CoreModels
    import Localization
    import XCTest

    /// Critical path: searching the current scope. Results come from the mocked search endpoint,
    /// which returns stable hits for any non empty query.
    final class SearchUITests: UITestCase {
        private func visibleSearchField(_ app: XCUIApplication) -> XCUIElement {
            let fields = app.textFields.matching(identifier: AccessibilityIdentifiers.Search.field)
            return fields.allElementsBoundByIndex.first { $0.isHittable } ?? fields.firstMatch
        }

        /// The root searches everywhere with no scope to choose, the Images chip narrows the hits,
        /// and clearing the query brings the listing back.
        func testRootSearchNarrowsByKindAndClearsBackToTheListing() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.folder).waitToAppear())
            XCTAssertTrue(browse.searchField.waitToAppear())
            browse.searchField.clearAndType(Fixture.searchQuery)

            XCTAssertTrue(browse.item(Fixture.widerSearchHit).waitToAppear(), "The root searches from the top")
            XCTAssertFalse(app.buttons[L10n.Browse.scopeEverywhere].exists, "There is no scope choice to make")
            XCTAssertFalse(app.buttons[L10n.Browse.scopeThisFolder].exists, "There is no scope choice to make")
            XCTAssertFalse(app.buttons[L10n.Browse.searchEverywhere].exists, "The root cannot be widened")

            // Both a document and an image hit come back before filtering.
            XCTAssertTrue(browse.item(Fixture.searchHit).waitToAppear())
            XCTAssertTrue(browse.item(Fixture.imageSearchHit).waitToAppear())
            let imagesChip = browse.filterChip(L10n.Filter.images)
            XCTAssertTrue(imagesChip.waitToAppear(), "An image result should surface an Images filter chip")
            imagesChip.tap()
            XCTAssertTrue(
                browse.item(Fixture.searchHit).waitToVanish(),
                "Filtering to Images should hide the document hit"
            )
            XCTAssertTrue(browse.item(Fixture.imageSearchHit).exists, "Filtering to Images should keep the image hit")

            browse.searchField.clearAndType("")
            XCTAssertTrue(browse.item(Fixture.folder).waitToAppear(), "Clearing search should return to the listing")
            XCTAssertFalse(
                browse.item(Fixture.imageSearchHit).appears(within: UITestTimeout.short),
                "Cleared search should drop the results"
            )
        }

        /// A folder search stays in the folder until widened; a new search after clearing starts in
        /// the folder again.
        func testFolderSearchWidensAndANewSearchStartsInTheFolder() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.folder).waitToAppear())
            // Pushing can drop the first tap, so retry until the folder's navigation bar proves the
            // push landed.
            openMenu({ browse.item(Fixture.folder).tap() }, until: browse.folderNavigationBar(Fixture.folder))

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

            field.clearAndType("")
            field.clearAndType(Fixture.searchQuery)
            XCTAssertTrue(browse.item(Fixture.searchHit).waitToAppear())
            XCTAssertTrue(
                browse.item(Fixture.widerSearchHit).waitToVanish(),
                "A new search starts inside the folder again"
            )
            XCTAssertTrue(widen.waitToAppear(), "Widening is on offer again")
        }
    }
#endif
