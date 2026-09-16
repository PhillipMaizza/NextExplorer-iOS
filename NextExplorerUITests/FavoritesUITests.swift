import XCTest

/// Critical path: the Favorites tab. Backed by the mocked favorites endpoint.
final class FavoritesUITests: UITestCase {
    func testFavoritesListShowsItems() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let favorites = FavoritesScreen(app: app)
        selectTab(TabBar(app: app).favorites, until: favorites.item(Fixture.folder))
        XCTAssertTrue(favorites.item(Fixture.folder).exists, "The mocked favorites should list the starred folder")
    }

    func testFavoritesEmptyState() {
        let app = launchApp(auth: .loggedIn, scenario: .empty)
        let favorites = FavoritesScreen(app: app)
        selectTab(TabBar(app: app).favorites, until: favorites.emptyMessage)
        XCTAssertTrue(favorites.emptyMessage.exists, "No favorites should show the empty state")
    }
}
