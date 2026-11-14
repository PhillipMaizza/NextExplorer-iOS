#if os(iOS)
    import Localization
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

        func testRemoveFromOfflineInAPinnedFilesPreviewTakesItOffTheTab() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.availableOfflineAction)
            browse.availableOfflineAction.tap()

            let offline = OfflineTabScreen(app: app)
            selectTab(TabBar(app: app).downloads, until: offline.row(Fixture.file))
            offline.row(Fixture.file).tap()
            XCTAssertTrue(browse.previewBackButton.waitToAppear(), "Tapping a pinned file opens its preview")

            let title = app.navigationBars.descendants(matching: .any).labeled(Fixture.file)
            openMenu({ title.tap() }, until: browse.removeFromOfflineAction)
            browse.removeFromOfflineAction.tap()
            XCTAssertTrue(browse.removeOfflineConfirmButton.waitToAppear(), "Removing asks first")
            browse.removeOfflineConfirmButton.tap()

            XCTAssertTrue(browse.previewBackButton.waitToVanish(), "The preview closes once its file leaves the tab")
            XCTAssertTrue(offline.row(Fixture.file).waitToVanish(), "The file is no longer listed as offline")
        }

        /// The mocked listing is the same in every folder, so the file under the pinned folder is
        /// reached through search, whose hits sit under Documents.
        func testAFileFoundInsideAPinnedFolderCanTakeTheFolderOffTheDeviceFromItsPreview() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.folder).waitToAppear())
            openMenu({ browse.row(Fixture.folder).longPress() }, until: browse.availableOfflineAction)
            browse.availableOfflineAction.tap()

            XCTAssertTrue(browse.searchField.waitToAppear())
            browse.searchField.clearAndType(Fixture.fileSearchTerm)
            XCTAssertTrue(browse.item(Fixture.searchHit).waitToAppear())
            browse.item(Fixture.searchHit).tap()
            XCTAssertTrue(browse.previewBackButton.waitToAppear(), "The file opens in its preview")

            let title = app.navigationBars.descendants(matching: .any).labeled(Fixture.searchHit)
            openMenu({ title.tap() }, until: browse.removeFromOfflineAction)
            XCTAssertTrue(browse.removeFromOfflineAction.isEnabled, "A file kept through its folder can be removed")
            browse.removeFromOfflineAction.tap()
            XCTAssertTrue(browse.removeOfflineConfirmButton.waitToAppear(), "Removing asks first")
            XCTAssertTrue(
                app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", Fixture.folder)).firstMatch.exists,
                "The confirmation names the folder that comes off the device"
            )
            browse.removeOfflineConfirmButton.tap()
            XCTAssertTrue(browse.removeOfflineConfirmButton.waitToVanish())
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

        func testNewOfflineFilesPutADotOnTheOfflineTabUntilItIsOpened() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.availableOfflineAction)
            browse.availableOfflineAction.tap()

            let tab = TabBar(app: app).downloads
            let marked = NSPredicate(format: "value CONTAINS %@", L10n.Offline.newFilesBadge)
            XCTAssertTrue(waitUntil(marked, on: tab), "A finished run marks the Offline tab")
            let offline = OfflineTabScreen(app: app)
            selectTab(tab, until: offline.row(Fixture.file))
            XCTAssertTrue(
                waitUntil(NSCompoundPredicate(notPredicateWithSubpredicate: marked), on: tab),
                "Opening Offline clears it"
            )
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

        func testPinnedItemsPickedInSelectModeAreRemovedFromOfflineOnly() {
            let app = launchApp(auth: .loggedIn, scenario: .normal, legacyDownloads: true)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
            openMenu({ browse.row(Fixture.file).longPress() }, until: browse.availableOfflineAction)
            browse.availableOfflineAction.tap()

            let offline = OfflineTabScreen(app: app)
            selectTab(TabBar(app: app).downloads, until: offline.row(Fixture.file))
            openMenu({ browse.moreMenu.tap() }, until: browse.selectMenuItem)
            browse.selectMenuItem.tap()

            let remove = offline.removeFromOfflineSelectionButton
            XCTAssertTrue(offline.row(Fixture.file).waitToAppear())
            XCTAssertFalse(remove.exists, "With nothing picked the bar offers nothing")
            offline.row(Fixture.file).tap()
            XCTAssertTrue(remove.waitToAppear(), "A picked pinned item offers Remove from Offline")
            XCTAssertTrue(remove.isEnabled(within: UITestTimeout.standard), "It can be tapped")
            XCTAssertFalse(offline.deleteAction.isEnabled, "Delete is only for files saved earlier")

            remove.tap()
            XCTAssertTrue(offline.removeConfirmButton.waitToAppear(), "Removing asks first")
            offline.removeConfirmButton.tap()

            XCTAssertTrue(offline.row(Fixture.file).waitToVanish(), "The pinned item leaves the tab")
            XCTAssertTrue(remove.waitToVanish(), "Select mode ends once it is removed")
            XCTAssertTrue(offline.row(legacyName).exists, "Files saved earlier stay")
        }

        func testTheSelectionMenuAppearsOnlyOnceSomethingIsSelected() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
            openMenu({ browse.moreMenu.tap() }, until: browse.selectMenuItem)
            browse.selectMenuItem.tap()

            let offlineButton = browse.offlineSelectionButton
            XCTAssertTrue(browse.row(Fixture.file).waitToAppear())
            XCTAssertFalse(browse.selectionActionsMenu.exists, "With nothing selected the menu is not offered")

            browse.row(Fixture.file).tap()
            openMenu({ browse.selectionActionsMenu.tap() }, until: offlineButton)
            XCTAssertTrue(offlineButton.isEnabled(within: UITestTimeout.standard), "A selection enables it")
        }
    }
#endif
