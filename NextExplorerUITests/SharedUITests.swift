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
            /// The edit page's one month expiry choice, as the system duration formatter spells it.
            static let monthPreset = "1 month"
            static let renamedLabel = "Summer 2026"
        }

        /// By me lists the mocked shares, a person filter narrows it until tapped again, expired items
        /// sit under their own heading, and With me lists what others sent.
        func testTheListsFilterAndSwitchSegments() {
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

            for _ in 0 ..< 4 where !shared.expiredHeader.exists {
                app.swipeUp()
            }
            XCTAssertTrue(shared.expiredHeader.waitToAppear(), "Expired items sit under their own heading")

            for _ in 0 ..< 4 where !shared.withMeSegment.isHittable {
                app.swipeDown()
            }
            tapCenter(of: shared.withMeSegment)
            XCTAssertTrue(shared.item(ShareFixture.withMe).waitToAppear(), "With me should list shares others sent")
        }

        /// A one share item opens straight on its page; an item with two opens on their list, a row
        /// pushes its page, and saving an edit there shows the new values without reopening. Back on
        /// the one share item, editing asks before discarding and saves, and deleting its only share
        /// closes the sheet and drops the row.
        func testItemSheetsEditSaveAndDeleteTheirShares() {
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

            app.swipeUp()
            XCTAssertTrue(shared.editShareButton.waitToAppear(), "The share page offers Edit")
            shared.editShareButton.tap()
            XCTAssertTrue(shared.labelField.waitToAppear(), "Edit opens on the label")
            shared.labelField.clearAndType(ShareFixture.renamedLabel)
            shared.saveEditButton.tap()
            XCTAssertTrue(shared.saveEditButton.waitToVanish(), "Saving pops back to the share page")
            XCTAssertTrue(
                shared.item(ShareFixture.renamedLabel).waitToAppear(),
                "The pushed page shows the saved label without reopening"
            )
            shared.backButton.tap()
            XCTAssertTrue(shared.closeSheetButton.waitToAppear(), "Back returns to the share list")
            shared.closeSheetButton.tap()
            XCTAssertTrue(shared.copyLinkButton.waitToVanish(), "Close dismisses the sheet")

            shared.item(ShareFixture.byMe).tap()
            XCTAssertTrue(shared.copyLinkButton.waitToAppear(), "A one share item opens straight on its page")
            app.swipeUp()
            XCTAssertTrue(shared.editShareButton.waitToAppear(), "The share page offers Edit")
            shared.editShareButton.tap()
            XCTAssertTrue(shared.saveEditButton.waitToAppear(), "Edit pushes its page inside the sheet")
            XCTAssertFalse(shared.saveEditButton.isEnabled, "Nothing to save before a change")

            app.swipeUp()
            let month = shared.expiryPreset(ShareFixture.monthPreset)
            XCTAssertTrue(month.waitToAppear(), "Expiry offers presets")
            month.tap()
            XCTAssertTrue(shared.saveEditButton.isEnabled, "A change lights up Save")

            shared.backEditButton.tap()
            XCTAssertTrue(shared.discardTitle.waitToAppear(), "Back with changes asks first")
            shared.keepEditingButton.tap()
            XCTAssertTrue(shared.discardTitle.waitToVanish(), "Keep editing returns to the form")

            shared.saveEditButton.tap()
            XCTAssertTrue(shared.savedToast.waitToAppear(), "Saving confirms with a toast")
            XCTAssertTrue(shared.saveEditButton.waitToVanish(), "Saving pops back to the share page")

            app.swipeUp()
            XCTAssertTrue(shared.deleteShareButton.waitToAppear(), "The share page ends with Delete")
            shared.deleteShareButton.tap()
            XCTAssertTrue(shared.confirmDeleteButton.waitToAppear(), "Delete asks first, on top of the sheet")
            shared.confirmDeleteButton.tap()
            XCTAssertTrue(shared.copyLinkButton.waitToVanish(), "Deleting the last share closes the sheet")
            XCTAssertTrue(shared.item(ShareFixture.byMe).waitToVanish(), "The item leaves the list")
        }
    }
#endif
