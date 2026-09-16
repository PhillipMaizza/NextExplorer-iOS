import XCTest

/// Critical path: the Settings tab renders and its controls respond. The mocked preferences and
/// system settings back every row.
final class SettingsUITests: UITestCase {
    func testSettingsTabShowsContent() {
        let app = launchApp(auth: .loggedIn)
        let settings = SettingsScreen(app: app)
        selectTab(TabBar(app: app).settings, until: settings.languageRow)

        XCTAssertTrue(settings.languageRow.exists, "Settings should list its General rows")
        XCTAssertTrue(settings.signOutButton.waitToAppear(), "Settings should expose Sign Out")
    }

    func testOpenLanguagePicker() {
        let app = launchApp(auth: .loggedIn)
        let settings = SettingsScreen(app: app)
        selectTab(TabBar(app: app).settings, until: settings.languageRow)

        settings.languageRow.tap()

        // The language screen pushes with its own navigation bar; a back button proves the push.
        XCTAssertTrue(settings.pushedBackButton.waitToAppear(), "Tapping Language should push its picker")
    }

    func testOpenThumbnailSettings() {
        let app = launchApp(auth: .loggedIn)
        let settings = SettingsScreen(app: app)
        selectTab(TabBar(app: app).settings, until: settings.languageRow)

        // The admin section sits below the fold; the List only materializes it once scrolled near.
        XCTAssertTrue(scrollTo(settings.thumbnailsRow, in: app), "Admin settings should expose the Thumbnails row")
        settings.thumbnailsRow.tap()
        XCTAssertTrue(settings.thumbnailSettingsTitle.waitToAppear(), "Thumbnails should push its settings screen")
    }

    func testTipJarSheetOpens() {
        let app = launchApp(auth: .loggedIn)
        let settings = SettingsScreen(app: app)
        selectTab(TabBar(app: app).settings, until: settings.languageRow)

        // The tip button lives in the version footer at the very bottom of the List.
        XCTAssertTrue(scrollTo(settings.tipButton, in: app), "The version footer should offer a tip button")
        settings.tipButton.tap()

        // The purchase itself is a StoreKit system flow; assert only that the sheet presents.
        XCTAssertTrue(settings.tipJarTitle.waitToAppear(), "Tapping the tip prompt should present the tip jar")
    }
}
