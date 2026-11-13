#if os(macOS)
    import CoreModels
    import Localization
    import XCTest

    /// The Offline section on the Mac: its sidebar entry, pinning from the context menu, opening a
    /// pinned folder, and removing a pin after a confirmation. The Mac keeps "Download" (to a folder).
    final class MacOfflineUITests: MacUITestCase {
        private func openOffline(in app: XCUIApplication) {
            let item = sidebarItem(L10n.Tab.offline, in: app)
            XCTAssertTrue(item.waitToAppear(), "The sidebar has an Offline section")
            item.click()
        }

        /// A row of the Offline table, found by its name cell like a Browse table row.
        private func offlineRow(_ name: String, in app: XCUIApplication) -> XCUIElement {
            text(name, in: app)
        }

        private func pin(_ name: String, in app: XCUIApplication) {
            XCTAssertTrue(text(name, in: app).waitToAppear())
            openMenu({ text(name, in: app).rightClick() }, until: app.menuItems[L10n.Browse.actionAvailableOffline])
            app.menuItems[L10n.Browse.actionAvailableOffline].click()
        }

        func testTheOfflineSectionIsInTheSidebarAndStartsEmpty() {
            let app = launchApp()
            openOffline(in: app)

            XCTAssertTrue(
                text(L10n.Offline.tabEmpty, in: app).waitToAppear(),
                "With nothing pinned the Offline section says so"
            )
            XCTAssertFalse(
                app.toolbars.buttons[L10n.Common.sort].exists,
                "The table sorts from its headers, so the section has no Sort button"
            )
        }

        func testPinningFromTheContextMenuListsTheFileInTheOfflineSection() {
            let app = launchApp()
            pin(Fixture.file, in: app)

            openOffline(in: app)

            XCTAssertTrue(offlineRow(Fixture.file, in: app).waitToAppear(), "A pinned file is listed in Offline")
            XCTAssertFalse(text(L10n.Offline.tabEmpty, in: app).exists)
        }

        func testTheMacKeepsDownloadNextToAvailableOffline() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.file, in: app).waitToAppear())
            openMenu({ text(Fixture.file, in: app).rightClick() }, until: app.menuItems[L10n.Browse.actionDownload])

            XCTAssertTrue(app.menuItems[L10n.Browse.actionDownload].exists, "The Mac still downloads to a folder")
            XCTAssertTrue(app.menuItems[L10n.Browse.actionAvailableOffline].exists)
            XCTAssertFalse(app.menuItems[L10n.Browse.actionSaveToDevice].exists, "Save to Device is the phone's action")
        }

        func testAPinnedFolderOpensFromTheOfflineSectionAndGoesBack() {
            let app = launchApp()
            pin(Fixture.folder, in: app)
            openOffline(in: app)
            XCTAssertTrue(offlineRow(Fixture.folder, in: app).waitToAppear())

            offlineRow(Fixture.folder, in: app).doubleClick()

            XCTAssertTrue(backButton(in: app).waitToAppear(UITestTimeout.standard, "A pinned folder opens in place"))
            backButton(in: app).click()
            XCTAssertTrue(offlineRow(Fixture.folder, in: app).waitToAppear(), "Back returns to the Offline list")
        }

        func testAPinnedFileOpensItsPreviewFromTheOfflineSection() {
            let app = launchApp()
            pin(Fixture.file, in: app)
            openOffline(in: app)
            XCTAssertTrue(offlineRow(Fixture.file, in: app).waitToAppear())

            offlineRow(Fixture.file, in: app).doubleClick()

            let sheet = app.sheets.firstMatch
            XCTAssertTrue(sheet.waitToAppear(), "Double clicking a pinned file opens its preview")
            XCTAssertTrue(sheet.buttons.labeled(L10n.PreviewToolbar.close).waitToAppear())
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            XCTAssertTrue(sheet.waitToVanish(), "Esc closes it, back on the Offline section")
        }

        func testRemovingAPinAsksFirstAndCancelKeepsIt() {
            let app = launchApp()
            pin(Fixture.file, in: app)
            openOffline(in: app)
            XCTAssertTrue(offlineRow(Fixture.file, in: app).waitToAppear())

            openMenu(
                { offlineRow(Fixture.file, in: app).rightClick() },
                until: app.menuItems[L10n.Common.remove]
            )
            app.menuItems[L10n.Common.remove].click()

            let confirm = app.labeledButton(L10n.Offline.removeConfirm)
            XCTAssertTrue(confirm.waitToAppear(), "Removing asks first")
            XCTAssertTrue(offlineRow(Fixture.file, in: app).exists, "The file stays while the question is open")
            app.labeledButton(L10n.Common.cancel).click()
            XCTAssertTrue(offlineRow(Fixture.file, in: app).waitToAppear(), "Cancel keeps the pin")
        }

        func testConfirmingTheRemovalEmptiesTheOfflineSection() {
            let app = launchApp()
            pin(Fixture.file, in: app)
            openOffline(in: app)
            XCTAssertTrue(offlineRow(Fixture.file, in: app).waitToAppear())

            openMenu(
                { offlineRow(Fixture.file, in: app).rightClick() },
                until: app.menuItems[L10n.Common.remove]
            )
            app.menuItems[L10n.Common.remove].click()
            app.labeledButton(L10n.Offline.removeConfirm).click()

            XCTAssertTrue(text(L10n.Offline.tabEmpty, in: app).waitToAppear(), "The last pin is gone")
        }
    }
#endif
