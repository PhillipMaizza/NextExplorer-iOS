#if os(iOS)
    import CoreModels
    import Localization
    import XCTest

    /// Critical path: the Favorites tab. Backed by the mocked favorites endpoint.
    final class FavoritesUITests: UITestCase {
        /// The seeded favorites show the starred folder, labels in place of names and a nested
        /// folder's own name, and a labelled one opens its folder; a folder starred in Browse then
        /// joins them, and removing one takes it off the list.
        func testFavoritesListOpenJoinAndLeave() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let favorites = FavoritesScreen(app: app)
            let bills = favorites.item(UITestFixture.FavoriteLabel.invoices.rawValue)
            selectTab(TabBar(app: app).favorites, until: favorites.item(Fixture.folder))
            XCTAssertTrue(bills.waitToAppear(), "A label replaces the folder name")
            XCTAssertTrue(favorites.item(UITestFixture.FavoriteLabel.teamLibrary.rawValue).exists)
            XCTAssertTrue(
                favorites.item(UITestFixture.Folder.website.name).exists,
                "A nested folder shows its own name"
            )
            openMenu({ bills.tap() }, until: favorites.item(UITestFixture.Folder.invoices2025.name))
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(bills.waitToAppear(), "Back returns to the favorites")

            let browse = BrowseScreen(app: app)
            selectTab(TabBar(app: app).browse, until: browse.item(Fixture.folderAlt))
            openMenu({ browse.row(Fixture.folderAlt).longPress() }, until: browse.addToFavoritesAction)
            browse.addToFavoritesAction.tap()
            selectTab(TabBar(app: app).favorites, until: favorites.item(Fixture.folderAlt))
            XCTAssertTrue(favorites.item(Fixture.folderAlt).exists, "A folder starred in Browse joins Favorites")

            let label = UITestFixture.FavoriteLabel.teamLibrary.rawValue
            openMenu({ favorites.row(label).longPress() }, until: favorites.removeAction)
            favorites.removeAction.tap()
            XCTAssertTrue(favorites.item(label).waitToVanish(), "A removed favorite leaves the list")
        }
    }
#endif
