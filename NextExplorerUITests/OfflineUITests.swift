#if os(iOS)
    import XCTest

    /// Critical path for offline downloads: the Settings row opens the chooser, selecting a file enables
    /// the download, and confirming dismisses the sheet. The mocked graph (`UITestSupport`) provides an
    /// instant `offlineDownloadFile` and an in memory offline store so the flow runs without a backend.
    final class OfflineUITests: UITestCase {
        func testSelectingAFileEnablesDownloadThenDismisses() {
            let app = launchApp(auth: .loggedIn)
            let settings = SettingsScreen(app: app)
            selectTab(TabBar(app: app).settings, until: settings.addAccountRow)

            XCTAssertTrue(scrollTo(settings.offlineDownloadRow, in: app))
            settings.offlineDownloadRow.tap()

            let picker = OfflineSelectionScreen(app: app)
            XCTAssertTrue(picker.itemRow("vacation.jpg").waitToAppear())
            XCTAssertFalse(picker.downloadButton.isEnabled, "Download starts disabled with nothing selected")

            picker.itemRow("vacation.jpg").tap()
            XCTAssertTrue(picker.downloadButton.isEnabled, "Selecting a file should enable Download")

            picker.downloadButton.tap()
            XCTAssertTrue(settings.offlineDownloadRow.waitToAppear(), "Confirming should dismiss the picker back to Settings")
        }
    }
#endif
