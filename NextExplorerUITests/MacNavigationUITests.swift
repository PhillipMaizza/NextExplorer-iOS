#if os(macOS)
    import CoreModels
    import Localization
    import XCTest

    /// The Mac window's sidebar, folder navigation, the Go menu and keyboard shortcuts.
    final class MacNavigationUITests: MacUITestCase {
        func testLoginJourneyRevealsTheSidebar() {
            let app = launchApp(auth: .loggedOut)
            LoginScreen(app: app).signIn()

            XCTAssertTrue(
                sidebarItem(L10n.Tab.browse, in: app).waitToAppear(),
                "A successful login should reveal the sidebar"
            )
        }

        /// Shared, ⌘2 Favorites and ⌘1 Browse switch sections, and Browse comes back on the folder it
        /// had open, without the pushed path trapping.
        func testSectionsSwitchAndBrowseKeepsTheOpenFolder() {
            let app = launchApp()
            openDocuments(in: app)

            sidebarItem(L10n.Tab.shared, in: app).click()
            XCTAssertTrue(text(Self.byMeShare, in: app).waitToAppear(), "Shared should list the links shared by me")

            app.typeKey("2", modifierFlags: .command)
            // Only the Favorites table has a Location column.
            XCTAssertTrue(app.buttons[L10n.FileInfo.rowLocation].waitToAppear(), "⌘2 should show Favorites")
            XCTAssertFalse(
                text(Self.byMeShare, in: app).appears(within: UITestTimeout.short),
                "Favorites should replace Shared"
            )

            app.typeKey("1", modifierFlags: .command)
            XCTAssertTrue(
                text(Fixture.file, in: app).waitToAppear(),
                "⌘1 should return to Browse on the folder it had open"
            )
            XCTAssertTrue(backButton(in: app).waitToAppear(), "The opened folder should still have Back")
        }

        /// Back leaves a folder; ⌘] and ⌘[ and the Go menu's Forward and Back walk the history.
        func testBackAndForwardFromTheButtonShortcutsAndGoMenu() {
            let app = launchApp()
            openDocuments(in: app)

            backButton(in: app).click()
            XCTAssertTrue(
                backButton(in: app).waitToVanish(),
                "Back should return to the root, which has no Back button"
            )

            app.typeKey("]", modifierFlags: .command)
            XCTAssertTrue(backButton(in: app).waitToAppear(), "⌘] should reopen the folder left by going back")
            XCTAssertTrue(text(Fixture.file, in: app).waitToAppear(), "The reopened folder should list its files")
            app.typeKey("[", modifierFlags: .command)
            XCTAssertTrue(backButton(in: app).waitToVanish(), "⌘[ should return to the root")

            goMenuItem(L10n.Menu.forward, in: app).click()
            XCTAssertTrue(backButton(in: app).waitToAppear(), "Forward should reopen the folder left by going back")
            XCTAssertTrue(text(Fixture.file, in: app).waitToAppear(), "The reopened folder should list its files")
            goMenuItem(L10n.Common.back, in: app).click()
            XCTAssertTrue(backButton(in: app).waitToVanish(), "Back should return to the root")
        }

        /// ⌘↓ opens the selected folder and ⌘↑ leaves it; after Go to Folder jumps to a nested
        /// folder, ⌘↑ opens its parent rather than dropping back to the root.
        func testCommandDownAndUpWalkFoldersAfterGoToFolder() {
            let app = launchApp()
            let folder = text(Fixture.folder, in: app)
            XCTAssertTrue(folder.waitToAppear())
            folder.waitToBeHittable()
            folder.click()
            app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: .command)
            XCTAssertTrue(backButton(in: app).waitToAppear(), "⌘↓ should open the selected folder")
            app.typeKey(XCUIKeyboardKey.upArrow, modifierFlags: .command)
            XCTAssertTrue(backButton(in: app).waitToVanish(), "⌘↑ from a top folder should reach the root")

            app.typeKey(Constants.goToFolderKey, modifierFlags: [.command, .shift])
            let field = app.textFields[L10n.Menu.goToFolderTitle]
            XCTAssertTrue(field.waitToAppear(), "⇧⌘G should ask for a folder")
            field.clearAndType(UITestFixture.Folder.invoices.path)
            app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
            XCTAssertTrue(
                windowTitled(UITestFixture.Folder.invoices.name, in: app).waitToAppear(),
                "Go to Folder should open the nested folder"
            )

            app.typeKey(XCUIKeyboardKey.upArrow, modifierFlags: .command)
            XCTAssertTrue(windowTitled(Fixture.folder, in: app).waitToAppear(), "⌘↑ should open the parent folder")
            XCTAssertTrue(backButton(in: app).exists, "The parent is a folder too, so Back stays")
        }

        /// Space on a folder opens Get Info beside the table, as in Finder, and the View menu's zoom
        /// items come alive while an image preview is open.
        func testSpaceOpensGetInfoAndZoomWorksInAnImagePreview() {
            let app = launchApp()
            let folder = text(Fixture.folder, in: app)
            XCTAssertTrue(folder.waitToAppear())
            folder.waitToBeHittable()
            folder.click()
            app.typeKey(XCUIKeyboardKey.space, modifierFlags: [])
            let close = app.labeledButton(L10n.Common.close)
            XCTAssertTrue(close.waitToAppear(), "Space should open Get Info for a folder")
            close.click()
            XCTAssertTrue(close.waitToVanish())

            let image = text(Fixture.imageFile, in: app)
            XCTAssertTrue(image.waitToAppear())
            image.waitToBeHittable()
            image.doubleClick()

            let viewMenu = app.menuBars.menuBarItems[Constants.viewMenu]
            let zoomIn = app.menuItems[L10n.Menu.zoomIn]
            viewMenu.click()
            if !zoomIn.isEnabled(within: UITestTimeout.standard) {
                // The preview may still be loading the first time the menu opens.
                app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
                viewMenu.click()
            }
            XCTAssertTrue(zoomIn.isEnabled, "Zoom In should be enabled over an image preview")
            zoomIn.click()
        }

        /// The Move dialog's folders open from the keyboard (⌘↓), not only by double click.
        func testMoveDialogOpensAFolderFromTheKeyboard() {
            let app = launchApp()
            let file = text(Fixture.file, in: app)
            XCTAssertTrue(file.waitToAppear())
            let move = app.menuItems[L10n.Browse.actionMove]
            openMenu({ file.rightClick() }, until: move)
            move.click()

            let sheet = app.sheets.firstMatch
            XCTAssertTrue(sheet.waitToAppear(), "Move should open the folder picker")
            let sheetBack = sheet.buttons.labeled(L10n.Common.back)
            XCTAssertTrue(sheetBack.waitToAppear())
            XCTAssertFalse(sheetBack.isEnabled, "The picker starts at the root")

            let folder = sheet.staticTexts.showing(Fixture.folderAlt)
            XCTAssertTrue(folder.waitToAppear(), "The picker should list the folders")
            folder.click()
            app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: .command)

            XCTAssertTrue(sheetBack.isEnabled(within: UITestTimeout.standard), "⌘↓ should open the selected folder")
        }
    }
#endif
