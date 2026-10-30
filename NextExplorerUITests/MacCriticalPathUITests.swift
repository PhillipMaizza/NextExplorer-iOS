#if os(macOS)
    import Localization
    import XCTest

    /// Critical paths of the Mac app against the same mocked backend as the iOS suite: the
    /// sidebar, the file tables, the menu bar, keyboard shortcuts, context menus and sheets.
    /// Runs on the Mac itself, so it drives the real pointer and keyboard while it runs.
    final class MacCriticalPathUITests: UITestCase {
        // MARK: Launch and navigation

        func testRestoredSessionShowsTheBrowseTable() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear(), "A restored session should list the root in the table")
            XCTAssertTrue(text(Fixture.file, in: app).exists)
        }

        func testNoStoredSessionShowsLogin() {
            let app = launchApp(auth: .loggedOut)
            XCTAssertTrue(LoginScreen(app: app).hostField.waitToAppear(), "No stored session should show the server entry page")
        }

        func testLoginJourneyRevealsTheSidebar() {
            let app = launchApp(auth: .loggedOut)
            let login = LoginScreen(app: app)
            XCTAssertTrue(login.hostField.waitToAppear())
            login.hostField.clearAndType("nextexplorer.example.com")
            login.testConnectionButton.click()

            XCTAssertTrue(login.emailField.waitToAppear(), "Test connection should advance to the credentials page")
            login.emailField.clearAndType("phillip@example.com")
            login.passwordField.clearAndType("hunter2")
            login.submitButton.click()

            XCTAssertTrue(sidebarItem(L10n.Tab.browse, in: app).waitToAppear(), "A successful login should reveal the sidebar")
        }

        func testSidebarSectionsAndShortcuts() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            // The first click on an inactive window only activates it.
            focusWindow(app)

            sidebarItem(L10n.Tab.shared, in: app).click()
            XCTAssertTrue(text(Self.byMeShare, in: app).waitToAppear(), "Shared should list the links shared by me")

            app.typeKey("2", modifierFlags: .command)
            // Only the Favorites table has a Location column.
            XCTAssertTrue(app.buttons[L10n.FileInfo.rowLocation].waitToAppear(), "⌘2 should show Favorites")
            XCTAssertFalse(text(Self.byMeShare, in: app).appears(within: UITestTimeout.short), "Favorites should replace Shared")

            app.typeKey("1", modifierFlags: .command)
            XCTAssertTrue(text(Fixture.imageFile, in: app).waitToAppear(), "⌘1 should return to Browse")
        }

        /// The split view stays put across sections; a folder opened in Browse survives a round
        /// trip through other sections without the pushed path trapping.
        func testSwitchingSectionsKeepsTheOpenFolder() {
            let app = launchApp()
            openDocuments(in: app)

            sidebarItem(L10n.Tab.shared, in: app).click()
            XCTAssertTrue(text(Self.byMeShare, in: app).waitToAppear(), "Shared should replace Browse")
            sidebarItem(L10n.Tab.favorites, in: app).click()
            XCTAssertTrue(app.buttons[L10n.FileInfo.rowLocation].waitToAppear(), "Favorites should replace Shared")
            sidebarItem(L10n.Tab.browse, in: app).click()

            XCTAssertTrue(text(Fixture.file, in: app).waitToAppear(), "Browse should come back on the folder it had open")
            XCTAssertTrue(backButton(in: app).waitToAppear(), "The opened folder should still have Back")
        }

        func testDoubleClickOpensAFolderAndBackReturns() {
            let app = launchApp()
            openDocuments(in: app)

            backButton(in: app).click()
            XCTAssertTrue(backButton(in: app).waitToVanish(), "Back should return to the root, which has no Back button")
        }

        // MARK: File actions

        func testCreateFolderFromTheFileMenu() {
            let app = launchApp()
            openDocuments(in: app)

            app.menuBars.menuBarItems["File"].click()
            app.menuItems[L10n.Browse.actionNewFolder].click()

            let field = app.textFields[L10n.Browse.newFolderPlaceholder]
            XCTAssertTrue(field.waitToAppear(), "Create Folder should present the name sheet")
            field.clearAndType("Reports")
            app.labeledButton(L10n.Browse.newFolderConfirm).click()

            XCTAssertTrue(field.waitToVanish(), "A successful create should dismiss the sheet")
            XCTAssertTrue(text("Reports", in: app).waitToAppear(), "The new folder should appear in the table")
        }

        func testRenameInPlaceFromTheContextMenu() {
            let app = launchApp()
            openDocuments(in: app)

            text(Fixture.file, in: app).rightClick()
            XCTAssertTrue(app.menuItems[L10n.Browse.actionRename].waitToAppear(), "Right click should offer Rename")
            app.menuItems[L10n.Browse.actionRename].click()

            // The name cell turns into a text field in place, Finder style, with no sheet.
            let field = app.outlines.textFields.firstMatch
            XCTAssertTrue(field.waitToAppear(), "Rename should edit the name in the table")
            field.clearAndType("todo.txt")
            app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

            XCTAssertTrue(field.waitToVanish(), "Return should finish the rename")
            XCTAssertTrue(text("todo.txt", in: app).waitToAppear(), "The renamed file should appear in the table")
        }

        func testReturnRenamesTheSelectedFile() {
            let app = launchApp()
            openDocuments(in: app)

            text(Fixture.file, in: app).click()
            app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

            // Finder style: Return edits the name in place instead of opening the file.
            let field = app.outlines.textFields.firstMatch
            XCTAssertTrue(field.waitToAppear(), "Return should rename the selected file in place")
            let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
            XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: UITestTimeout.short), .completed, "The rename field should take keyboard focus")
            field.clearAndType("todo.txt")
            app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
            XCTAssertTrue(field.waitToVanish(), "Return in the field should finish the rename")
            XCTAssertTrue(text("todo.txt", in: app).waitToAppear(), "The renamed file should appear in the table")
        }

        func testDeleteKeyAsksBeforeDeleting() {
            let app = launchApp()
            openDocuments(in: app)

            text(Fixture.file, in: app).click()
            app.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])

            let confirm = app.labeledButton(L10n.Common.delete)
            XCTAssertTrue(confirm.waitToAppear(), "Delete should ask for confirmation first")
            confirm.click()

            XCTAssertTrue(text(Fixture.file, in: app).waitToVanish(), "The confirmed file should leave the table")
        }

        // MARK: Search, refresh

        func testFindFocusesTheToolbarSearch() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            focusWindow(app)

            app.typeKey("f", modifierFlags: .command)
            let field = app.searchFields.firstMatch
            let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
            XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: UITestTimeout.standard), .completed, "⌘F should focus the toolbar search")
            app.typeText(Fixture.searchQuery)

            // A result row carries its name on the row itself rather than a separate text.
            let hit = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", Fixture.searchHit, Fixture.searchHit))
                .firstMatch
            XCTAssertTrue(hit.waitToAppear(), "⌘F then typing should show the search results")
        }

        /// Typing in the toolbar search, with pauses long enough for the search to run between
        /// keys, keeps every keystroke in the field.
        func testTypingInSearchKeepsTheFieldFocused() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            focusWindow(app)
            app.typeKey("f", modifierFlags: .command)
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitToAppear())

            for character in Fixture.folderAlt {
                app.typeText(String(character))
                // Past the search debounce, so each partial query has run before the next key.
                Thread.sleep(forTimeInterval: 1.3)
            }
            let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
            XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: UITestTimeout.short), .completed, "The search field should keep focus while typing")
            XCTAssertEqual(field.value as? String, Fixture.folderAlt, "Every keystroke should land in the search field")
        }

        /// A folder found by search opens and loads like one opened from the table.
        func testOpeningAFolderFromSearchLoadsIt() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            focusWindow(app)
            app.typeKey("f", modifierFlags: .command)
            app.typeText(Fixture.folderAlt)

            let hit = app.outlines.cells.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", Fixture.folderAlt, Fixture.folderAlt)).firstMatch
            XCTAssertTrue(hit.waitToAppear(), "The folder should be among the search results")
            hit.doubleClick()

            XCTAssertTrue(backButton(in: app).waitToAppear(), "Opening the result should push the folder")
            XCTAssertTrue(text(Fixture.file, in: app).waitToAppear(), "The opened folder should load its files, not stay on the skeleton")
        }

        func testRefreshShortcutConfirmsTheSync() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            focusWindow(app)

            app.typeKey("r", modifierFlags: .command)
            XCTAssertTrue(text(L10n.Common.syncCompleted, in: app).waitToAppear(), "⌘R should refresh and confirm it")
        }

        // MARK: Shared, Settings, account

        func testSharedSegmentsAndEditFromTheContextMenu() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            focusWindow(app)
            sidebarItem(L10n.Tab.shared, in: app).click()
            XCTAssertTrue(text(Self.byMeShare, in: app).waitToAppear())

            segment(L10n.Shared.segmentWithMe, in: app).click()
            XCTAssertTrue(text(Self.withMeShare, in: app).waitToAppear(), "With me should list links shared with me")

            segment(L10n.Shared.segmentByMe, in: app).click()
            XCTAssertTrue(text(Self.byMeShare, in: app).waitToAppear())
            text(Self.byMeShare, in: app).rightClick()
            XCTAssertTrue(app.menuItems[L10n.Common.edit].waitToAppear(), "A share I own should offer Edit")
            app.menuItems[L10n.Common.edit].click()

            XCTAssertTrue(text(L10n.EditShare.title, in: app).waitToAppear(), "Edit should open the edit share sheet")
        }

        func testSettingsWindowToggleFlips() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            focusWindow(app)
            // Settings lives in its own window on the Mac, opened from the app menu.
            app.typeKey(",", modifierFlags: .command)

            let toggle = app.descendants(matching: .any)
                .matching(NSPredicate(format: "(elementType == %d OR elementType == %d) AND label == %@",
                                      XCUIElement.ElementType.switch.rawValue,
                                      XCUIElement.ElementType.checkBox.rawValue,
                                      L10n.Settings.toggleShowHiddenFiles))
                .firstMatch
            // A fresh launch can drop the first ⌘, while its menu bar is still settling.
            if !toggle.appears(within: UITestTimeout.short) {
                focusWindow(app)
                app.typeKey(",", modifierFlags: .command)
            }
            XCTAssertTrue(toggle.waitToAppear(), "Settings should show the hidden files toggle")
            let before = toggle.value as? Int
            toggle.click()

            let flipped = NSPredicate(format: "value != %@", NSNumber(value: before ?? 0))
            let expectation = XCTNSPredicateExpectation(predicate: flipped, object: toggle)
            XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: UITestTimeout.standard), .completed, "Clicking should flip the toggle")
        }

        func testSignOutFromTheAccountMenu() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())

            app.labeledButton(L10n.Settings.sectionAccounts).click()
            let signOut = app.labeledButton(L10n.Settings.signOutButton)
            XCTAssertTrue(signOut.waitToAppear(), "The account menu should offer Sign Out")
            signOut.click()

            let confirm = app.labeledButton(L10n.Common.logOut)
            XCTAssertTrue(confirm.waitToAppear(), "Sign out should ask for confirmation")
            confirm.click()

            XCTAssertTrue(LoginScreen(app: app).hostField.waitToAppear(), "Signing out should return to login")
        }

        // MARK: Helpers

        /// A by me link and the with me link in the mocked shares.
        private static let byMeShare = "Electricity"
        private static let withMeShare = "Team Roadmap"

        /// Text on screen, matched by label or value: table cells expose their text as a value.
        private func text(_ string: String, in app: XCUIApplication) -> XCUIElement {
            app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", string, string)).firstMatch
        }

        /// A section in the main window's sidebar, a native selectable list row on the Mac.
        private func sidebarItem(_ title: String, in app: XCUIApplication) -> XCUIElement {
            app.outlines.cells.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", title, title)).firstMatch
        }

        private func backButton(in app: XCUIApplication) -> XCUIElement {
            app.toolbars.buttons.matching(NSPredicate(format: "label == %@", L10n.Common.back)).firstMatch
        }

        /// A segment of a native segmented control, which the Mac exposes as a radio button.
        private func segment(_ title: String, in app: XCUIApplication) -> XCUIElement {
            app.radioButtons.matching(NSPredicate(format: "label == %@ OR title == %@", title, title)).firstMatch
        }

        /// Clicks into the table so the window is key: menu commands that act on the visible
        /// screen (⌘F, ⌘R) read it from the key window, which a fresh test launch may not have yet.
        private func focusWindow(_ app: XCUIApplication) {
            text(Fixture.folder, in: app).click()
        }

        private func openDocuments(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
            let folder = text(Fixture.folder, in: app)
            XCTAssertTrue(folder.waitToAppear(file: file, line: line))
            folder.waitToBeHittable(file: file, line: line)
            // The table can still be rebuilding its rows right after launch, which drops the first
            // double click; one retry covers it.
            folder.doubleClick()
            if !backButton(in: app).appears(within: UITestTimeout.short) {
                text(Fixture.folder, in: app).doubleClick()
            }
            XCTAssertTrue(backButton(in: app).waitToAppear(UITestTimeout.standard, "Double click should open the folder", file: file, line: line))
        }
    }
#endif
