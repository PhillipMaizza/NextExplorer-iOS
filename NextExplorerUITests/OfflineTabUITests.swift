#if os(iOS)
    import XCTest

    /// Offline and Save to Device on iPhone: the per item actions, the Offline tab that replaced
    /// Downloads, and files an earlier version saved into the app, which must keep listing and deleting.
    final class OfflineTabUITests: UITestCase {
        private let legacyName = "legacy-report.pdf"

        func testFilesSavedByAnEarlierVersionStillListInTheOfflineTab() {
            let app = launchApp(auth: .loggedIn, scenario: .normal, legacyDownloads: true)
            let offline = OfflineTabScreen(app: app)
            selectTab(TabBar(app: app).downloads, until: offline.row(legacyName))

            XCTAssertTrue(offline.row(legacyName).exists, "A file saved before the Offline tab must still be listed")
        }

        func testAFileSavedByAnEarlierVersionCanStillBeDeleted() {
            let app = launchApp(auth: .loggedIn, scenario: .normal, legacyDownloads: true)
            let offline = OfflineTabScreen(app: app)
            selectTab(TabBar(app: app).downloads, until: offline.row(legacyName))

            openMenu({ offline.row(legacyName).press(forDuration: 1) }, until: offline.deleteAction)
            offline.deleteAction.tap()
            XCTAssertTrue(offline.deleteAction.waitToAppear(), "Delete asks for confirmation first")
            offline.deleteAction.tap()

            XCTAssertTrue(offline.row(legacyName).waitToVanish(), "A confirmed delete removes the saved file")
            XCTAssertTrue(offline.emptyMessage.waitToAppear(), "With nothing left the tab shows its empty state")
        }

        func testMakingAFileAvailableOfflineListsItNextToEarlierDownloads() {
            let app = launchApp(auth: .loggedIn, scenario: .normal, legacyDownloads: true)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.availableOfflineAction)
            browse.availableOfflineAction.tap()

            let offline = OfflineTabScreen(app: app)
            selectTab(TabBar(app: app).downloads, until: offline.row(Fixture.file))

            XCTAssertTrue(offline.row(Fixture.file).waitToAppear(), "A pinned file is listed in the Offline tab")
            XCTAssertTrue(offline.row(legacyName).exists, "Earlier downloads stay listed under it")
            XCTAssertTrue(offline.savedEarlierHeader.exists, "Earlier downloads get their own heading")
        }

        func testAPinnedFolderOpensFromTheOfflineTab() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.folder).waitToAppear())
            openMenu({ browse.row(Fixture.folder).longPress() }, until: browse.availableOfflineAction)
            browse.availableOfflineAction.tap()

            let offline = OfflineTabScreen(app: app)
            selectTab(TabBar(app: app).downloads, until: offline.row(Fixture.folder))
            offline.row(Fixture.folder).tap()

            XCTAssertTrue(offline.backButton.waitToAppear(), "Tapping a pinned folder opens it, with a way back")
            offline.backButton.tap()
            XCTAssertTrue(offline.row(Fixture.folder).waitToAppear(), "Back returns to the Offline list")
        }

        func testAPinnedFileOpensItsPreviewFromTheOfflineTab() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.availableOfflineAction)
            browse.availableOfflineAction.tap()

            let offline = OfflineTabScreen(app: app)
            selectTab(TabBar(app: app).downloads, until: offline.row(Fixture.file))
            offline.row(Fixture.file).tap()

            XCTAssertTrue(browse.previewBackButton.waitToAppear(), "Tapping a pinned file opens its preview")
            browse.previewBackButton.tap()
            XCTAssertTrue(offline.row(Fixture.file).waitToAppear(), "Closing the preview returns to the Offline tab")
        }

        func testAFileOffersSaveToDeviceAndNoLongerOffersDownload() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.saveToDeviceAction)

            XCTAssertTrue(browse.saveToDeviceAction.exists)
            XCTAssertTrue(browse.availableOfflineAction.exists, "Offline is its own action next to Save to Device")
            XCTAssertFalse(browse.downloadAction.exists, "Download is gone on iPhone")
        }

        func testAFolderOffersAvailableOfflineButNotSaveToDevice() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.folder).waitToAppear())
            openMenu({ browse.row(Fixture.folder).longPress() }, until: browse.availableOfflineAction)

            XCTAssertTrue(browse.availableOfflineAction.exists)
            XCTAssertFalse(browse.saveToDeviceAction.exists, "Save to Device takes files only")
        }

        func testRemovingFromAvailableOfflineAsksFirstAndKeepsTheFileWhenCancelled() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.availableOfflineAction)
            browse.availableOfflineAction.tap()

            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.removeFromOfflineAction)
            browse.removeFromOfflineAction.tap()
            XCTAssertTrue(browse.removeOfflineConfirmButton.waitToAppear(), "Removing must ask first")
            browse.cancelButton.tap()
            XCTAssertTrue(browse.removeOfflineConfirmButton.waitToVanish())

            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.removeFromOfflineAction)
            XCTAssertTrue(browse.removeFromOfflineAction.exists, "Cancelling keeps the file available offline")
        }

        func testConfirmingRemovalMakesTheFileAvailableToPinAgain() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.availableOfflineAction)
            browse.availableOfflineAction.tap()

            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.removeFromOfflineAction)
            browse.removeFromOfflineAction.tap()
            XCTAssertTrue(browse.removeOfflineConfirmButton.waitToAppear())
            browse.removeOfflineConfirmButton.tap()
            XCTAssertTrue(browse.removeOfflineConfirmButton.waitToVanish())

            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.availableOfflineAction)
            XCTAssertTrue(browse.availableOfflineAction.exists, "After removal the file can be made available again")
        }

        func testRemovingAPinnedFileFromTheOfflineTabAsksFirst() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.availableOfflineAction)
            browse.availableOfflineAction.tap()

            let offline = OfflineTabScreen(app: app)
            selectTab(TabBar(app: app).downloads, until: offline.row(Fixture.file))
            offline.row(Fixture.file).swipeLeft()
            XCTAssertTrue(offline.removeAction.waitToAppear())
            offline.removeAction.tap()

            XCTAssertTrue(offline.removeConfirmButton.waitToAppear(), "Removing from the tab asks first")
            offline.removeConfirmButton.tap()
            XCTAssertTrue(offline.row(Fixture.file).waitToVanish(), "A confirmed removal empties the tab")
        }

        func testTheSelectionBarOfflineButtonNeedsASelection() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
            openMenu({ browse.moreMenu.tap() }, until: browse.selectMenuItem)
            browse.selectMenuItem.tap()

            let offlineButton = browse.offlineSelectionButton
            XCTAssertTrue(offlineButton.waitToAppear(), "Select mode offers Available Offline")
            XCTAssertFalse(offlineButton.isEnabled, "With nothing selected it is disabled")

            browse.row(Fixture.file).tap()
            XCTAssertTrue(offlineButton.isEnabled(within: UITestTimeout.standard), "A selection enables it")
        }
    }
#endif
