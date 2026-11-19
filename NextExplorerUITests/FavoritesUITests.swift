#if os(iOS)
    import CoreModels
    import Localization
    import XCTest

    /// Critical path: the Favorites tab. Backed by the mocked favorites endpoint.
    final class FavoritesUITests: UITestCase {
        func testFavoritesListShowsItems() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let favorites = FavoritesScreen(app: app)
            selectTab(TabBar(app: app).favorites, until: favorites.item(Fixture.folder))
            XCTAssertTrue(favorites.item(Fixture.folder).exists, "The mocked favorites should list the starred folder")
        }

        func testSeededFavoritesShowTheirLabelsAndNestedFolderNames() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let favorites = FavoritesScreen(app: app)
            selectTab(TabBar(app: app).favorites, until: favorites.item(Fixture.folder))
            XCTAssertTrue(
                favorites.item(UITestFixture.FavoriteLabel.invoices.rawValue).exists,
                "A label replaces the folder name"
            )
            XCTAssertTrue(favorites.item(UITestFixture.FavoriteLabel.teamLibrary.rawValue).exists)
            XCTAssertTrue(
                favorites.item(UITestFixture.Folder.website.name).exists,
                "A nested folder shows its own name"
            )
        }

        func testALabelledFavoriteOpensItsFolder() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let favorites = FavoritesScreen(app: app)
            let bills = favorites.item(UITestFixture.FavoriteLabel.invoices.rawValue)
            selectTab(TabBar(app: app).favorites, until: bills)
            openMenu({ bills.tap() }, until: favorites.item(UITestFixture.Folder.invoices2025.name))
        }

        func testRemovingAFavoriteTakesItOffTheList() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let favorites = FavoritesScreen(app: app)
            let label = UITestFixture.FavoriteLabel.teamLibrary.rawValue
            selectTab(TabBar(app: app).favorites, until: favorites.item(label))
            openMenu({ favorites.row(label).longPress() }, until: favorites.removeAction)
            favorites.removeAction.tap()
            XCTAssertTrue(favorites.item(label).waitToVanish(), "A removed favorite leaves the list")
        }

        func testAFolderStarredInBrowseJoinsFavorites() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.folderAlt).waitToAppear())
            openMenu({ browse.row(Fixture.folderAlt).longPress() }, until: browse.addToFavoritesAction)
            browse.addToFavoritesAction.tap()

            let favorites = FavoritesScreen(app: app)
            selectTab(TabBar(app: app).favorites, until: favorites.item(Fixture.folderAlt))
        }

        func testFavoritesThatFailToLoadSaySo() {
            let app = launchApp(failing: [.favorites])
            selectTab(TabBar(app: app).favorites, until: app.staticTexts.showingPart(L10n.Error.network))
        }

        func testFavoritesEmptyState() {
            let app = launchApp(auth: .loggedIn, scenario: .empty)
            let favorites = FavoritesScreen(app: app)
            selectTab(TabBar(app: app).favorites, until: favorites.emptyMessage)
            XCTAssertTrue(favorites.emptyMessage.exists, "No favorites should show the empty state")
        }
    }
#endif
