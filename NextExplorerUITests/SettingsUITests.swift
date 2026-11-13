#if os(iOS)
    import XCTest

    /// Critical path: the Settings tab renders and its controls respond. The mocked preferences and
    /// system settings back every row.
    final class SettingsUITests: UITestCase {
        func testOpenLanguagePicker() {
            let app = launchApp(auth: .loggedIn)
            let settings = SettingsScreen(app: app)
            selectTab(TabBar(app: app).settings, until: settings.addAccountRow)

            XCTAssertTrue(
                scrollTo(settings.pageRow("general"), in: app),
                "General should be a row on the Settings root"
            )
            settings.pageRow("general").tap()
            XCTAssertTrue(scrollTo(settings.languageRow, in: app), "Language row should be on the General page")
            settings.languageRow.tap()

            XCTAssertTrue(
                settings.languagePickerSystemDefaultSubtitle.waitToAppear(),
                "Tapping Language should push its picker"
            )
        }

        func testOpenThumbnailSettings() {
            let app = launchApp(auth: .loggedIn)
            let settings = SettingsScreen(app: app)
            selectTab(TabBar(app: app).settings, until: settings.addAccountRow)

            XCTAssertTrue(scrollTo(settings.pageRow("administration"), in: app), "An admin should see the Admin row")
            settings.pageRow("administration").tap()
            XCTAssertTrue(settings.thumbnailsRow.waitToAppear(), "The Admin page should expose the Thumbnails row")
            settings.thumbnailsRow.tap()
            XCTAssertTrue(settings.thumbnailSettingsTitle.waitToAppear(), "Thumbnails should push its settings screen")
        }

        func testTipJarSheetOpens() {
            let app = launchApp(auth: .loggedIn)
            let settings = SettingsScreen(app: app)
            selectTab(TabBar(app: app).settings, until: settings.addAccountRow)

            // The tip button lives in the version footer at the very bottom of the List.
            XCTAssertTrue(scrollTo(settings.tipButton, in: app), "The version footer should offer a tip button")
            settings.tipButton.tap()

            // The purchase itself is a StoreKit system flow; assert only that the sheet presents.
            XCTAssertTrue(settings.tipJarTitle.waitToAppear(), "Tapping the tip prompt should present the tip jar")
        }
    }
#endif
