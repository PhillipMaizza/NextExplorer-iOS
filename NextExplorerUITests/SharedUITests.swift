#if os(iOS)
    import XCTest

    /// Critical path: the Shared tab, its By me / With me segments, and their lists. Backed by the
    /// mocked share endpoints.
    final class SharedUITests: UITestCase {
        /// Labels the mocked share fixtures carry (Share.previewSharedByMe / previewSharedWithMe).
        private enum ShareFixture {
            static let byMe = "Electricity"
            static let withMe = "Team Roadmap"
            /// Shared only with Lea, whose filter id is `person.u6`.
            static let leaOnly = "Contract draft.pdf"
            static let lea = "person.u6"
            /// Two shares, so its sheet opens on a list; one of them carries this label.
            static let twoShares = "Vacation Photos"
            static let twoSharesLabel = "Family trip"
        }

        func testSharedByMeListShowsItems() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let shared = SharedScreen(app: app)
            selectTab(TabBar(app: app).shared, until: shared.item(ShareFixture.byMe))
            XCTAssertTrue(shared.item(ShareFixture.byMe).exists, "By me should list the mocked shares")
        }

        func testSwitchToWithMeSegment() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let shared = SharedScreen(app: app)
            selectTab(TabBar(app: app).shared, until: shared.byMeSegment)

            tapCenter(of: shared.withMeSegment)
            XCTAssertTrue(shared.item(ShareFixture.withMe).waitToAppear(), "With me should list shares others sent")
        }

        func testTappingAPersonFiltersAndTappingAgainClears() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let shared = SharedScreen(app: app)
            selectTab(TabBar(app: app).shared, until: shared.item(ShareFixture.byMe))

            shared.filter(ShareFixture.lea).tap()
            XCTAssertTrue(
                waitUntil(NSPredicate(format: "exists == false"), on: shared.item(ShareFixture.byMe)),
                "A public link only item leaves the list under a person filter"
            )
            XCTAssertTrue(shared.item(ShareFixture.leaOnly).exists, "Items shared with Lea stay")
            XCTAssertTrue(shared.filter(ShareFixture.lea).isSelected)

            shared.filter(ShareFixture.lea).tap()
            XCTAssertTrue(
                shared.item(ShareFixture.byMe).waitToAppear(),
                "Tapping the active person again clears the filter"
            )
            XCTAssertTrue(shared.filter("all").isSelected, "All is selected again")
        }

        func testFullyExpiredItemsGetTheirOwnSection() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let shared = SharedScreen(app: app)
            selectTab(TabBar(app: app).shared, until: shared.item(ShareFixture.byMe))

            app.swipeUp()
            app.swipeUp()
            XCTAssertTrue(shared.expiredHeader.waitToAppear(), "Expired items sit under their own heading")
        }

        func testTappingAnItemOpensItsSheetAndTheListPushesAShare() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let shared = SharedScreen(app: app)
            selectTab(TabBar(app: app).shared, until: shared.item(ShareFixture.byMe))

            shared.item(ShareFixture.byMe).tap()
            XCTAssertTrue(shared.copyLinkButton.waitToAppear(), "A one share item opens straight on its page")
            shared.closeSheetButton.tap()
            XCTAssertTrue(shared.copyLinkButton.waitToVanish(), "Close dismisses the sheet")

            shared.item(ShareFixture.twoShares).tap()
            XCTAssertTrue(
                shared.item(ShareFixture.twoSharesLabel).waitToAppear(),
                "An item with two shares opens on their list"
            )
            XCTAssertFalse(shared.copyLinkButton.exists, "The list has no page level copy button")
            shared.item(ShareFixture.twoSharesLabel).tap()
            XCTAssertTrue(shared.copyLinkButton.waitToAppear(), "A row pushes its share page")
        }

        func testSharedEmptyState() {
            let app = launchApp(auth: .loggedIn, scenario: .empty)
            let shared = SharedScreen(app: app)
            selectTab(TabBar(app: app).shared, until: shared.emptyByMe)
            XCTAssertTrue(shared.emptyByMe.exists, "No shares should show the empty state")
        }
    }
#endif
