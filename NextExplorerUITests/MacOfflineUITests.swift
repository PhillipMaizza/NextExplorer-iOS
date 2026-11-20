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

        /// One launch through the section: it starts empty with no Sort button; the file menu keeps
        /// Download next to Available Offline; a pin marks the sidebar until Offline opens, lists
        /// there and opens its preview; removing asks first, Cancel keeps it, and confirming empties
        /// the section again.
        func testAPinListsOpensAndLeavesTheOfflineSection() {
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

            sidebarItem(L10n.Tab.browse, in: app).click()
            XCTAssertTrue(text(Fixture.file, in: app).waitToAppear())
            openMenu({ text(Fixture.file, in: app).rightClick() }, until: app.menuItems[L10n.Browse.actionDownload])
            XCTAssertTrue(app.menuItems[L10n.Browse.actionAvailableOffline].exists)
            XCTAssertFalse(app.menuItems[L10n.Browse.actionSaveToDevice].exists, "Save to Device is the phone's action")
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

            pinForOffline(Fixture.file, in: app)
            let dot = newFilesDot(in: app)
            XCTAssertTrue(dot.exists, "A finished run marks Offline in the sidebar")
            openOffline(in: app)
            XCTAssertTrue(offlineRow(Fixture.file, in: app).waitToAppear(), "A pinned file is listed in Offline")
            XCTAssertTrue(dot.waitToVanish(), "Opening Offline clears it")
            XCTAssertFalse(
                app.toolbars.buttons[L10n.Menu.activity].exists,
                "An offline run shows in the bottom bar, never as the toolbar's transfers button"
            )

            offlineRow(Fixture.file, in: app).doubleClick()
            let sheet = app.sheets.firstMatch
            XCTAssertTrue(sheet.waitToAppear(), "Double clicking a pinned file opens its preview")
            XCTAssertTrue(sheet.buttons.labeled(L10n.PreviewToolbar.close).waitToAppear())
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            XCTAssertTrue(sheet.waitToVanish(), "Esc closes it, back on the Offline section")

            let remove = app.menuItems[L10n.Common.remove]
            let confirm = app.labeledButton(L10n.Offline.removeConfirm)
            openMenu({ offlineRow(Fixture.file, in: app).rightClick() }, until: remove)
            remove.click()
            XCTAssertTrue(confirm.waitToAppear(), "Removing asks first")
            XCTAssertTrue(offlineRow(Fixture.file, in: app).exists, "The file stays while the question is open")
            app.labeledButton(L10n.Common.cancel).click()
            XCTAssertTrue(confirm.waitToVanish())
            XCTAssertTrue(offlineRow(Fixture.file, in: app).exists, "Cancel keeps the pin")

            openMenu({ offlineRow(Fixture.file, in: app).rightClick() }, until: remove)
            remove.click()
            XCTAssertTrue(confirm.waitToAppear())
            confirm.click()
            XCTAssertTrue(text(L10n.Offline.tabEmpty, in: app).waitToAppear(), "The last pin is gone")
        }

        func testAPinnedFolderOpensFromTheOfflineSectionAndGoesBack() {
            let app = launchApp()
            pinForOffline(Fixture.folder, in: app, waitsForRun: false)
            openOffline(in: app)
            XCTAssertTrue(offlineRow(Fixture.folder, in: app).waitToAppear())

            offlineRow(Fixture.folder, in: app).doubleClick()

            XCTAssertTrue(backButton(in: app).waitToAppear(UITestTimeout.standard, "A pinned folder opens in place"))
            backButton(in: app).click()
            XCTAssertTrue(offlineRow(Fixture.folder, in: app).waitToAppear(), "Back returns to the Offline list")
        }
    }
#endif
