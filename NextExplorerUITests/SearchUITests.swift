import Localization
import XCTest

/// Critical path: searching the current scope. Results come from the mocked search endpoint,
/// which returns stable hits for any non empty query.
final class SearchUITests: UITestCase {
    func testSearchShowsResults() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(TabBar(app: app).browse.waitToAppear())

        XCTAssertTrue(browse.searchField.waitToAppear(), "Browse should expose the pinned search field")
        browse.searchField.clearAndType(Fixture.searchQuery)

        XCTAssertTrue(browse.item(Fixture.searchHit).waitToAppear(), "Typing a query should surface matching results")
    }

    func testSearchNoMatchesShowsEmptyState() {
        let app = launchApp(auth: .loggedIn, scenario: .empty)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(TabBar(app: app).browse.waitToAppear())

        XCTAssertTrue(browse.searchField.waitToAppear())
        browse.searchField.clearAndType(Fixture.searchQuery)

        // The empty scenario's search returns nothing, so no result row should appear.
        XCTAssertFalse(browse.item(Fixture.searchHit).appears(within: UITestTimeout.short), "An empty search should not show results")
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
        XCTAssertFalse(browse.item(Fixture.searchHit).appears(within: UITestTimeout.short), "Cleared search should drop the results")
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

        XCTAssertTrue(browse.item(Fixture.searchHit).waitToVanish(), "Filtering to Images should hide the document hit")
        XCTAssertTrue(browse.item(Fixture.imageSearchHit).exists, "Filtering to Images should keep the image hit")
    }
}
