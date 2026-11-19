#if os(macOS)
    import CoreModels
    import Localization
    import XCTest

    /// The Mac against the mocked world's own states, matching the iPhone suites: the browse tree's
    /// read only, empty and deep folders, the seeded trash and favorites, the admin panes, and each
    /// area's empty and failing answer.
    final class MacWorldUITests: MacUITestCase {
        private typealias Folder = UITestFixture.Folder
        private typealias Person = UITestFixture.ManagedUser
        private typealias Entry = UITestFixture.TrashEntry

        private enum Constants {
            /// Every row of the Settings sidebar, the most arrow presses any pane needs.
            static let settingsSidebarRows = 17
        }

        private func open(_ folder: Folder, in app: XCUIApplication) {
            let row = text(folder.name, in: app)
            XCTAssertTrue(row.waitToAppear(), "\(folder) is listed")
            row.waitToBeHittable()
            openMenu({ row.doubleClick() }, until: windowTitled(folder.name, in: app))
        }

        private func shows(_ part: String, in app: XCUIApplication) -> XCUIElement {
            app.staticTexts.showingPart(part)
        }

        /// Whether the open context menu offers `title`: the menu bar's Edit menu always holds a Delete
        /// of its own, so only an item beyond the menu bar's count is the context menu's.
        private func contextMenuOffers(_ title: String, in app: XCUIApplication) -> Bool {
            let titled = NSPredicate(format: "title == %@ AND enabled == true", title)
            return app.menuItems.matching(titled).count > app.menuBars.menuItems.matching(titled).count
        }

        /// The Settings window on one of its panes, picked in its sidebar. Sidebar rows read their
        /// names as a value, and the lower ones only exist once scrolled to, so the arrow keys walk
        /// down from General, which is always in view.
        private func openSettingsPane(_ title: String, in app: XCUIApplication) {
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            let general = text(L10n.Settings.sectionGeneral, in: app)
            openSettingsWindow(in: app, until: general)
            general.click()
            let pane = text(title, in: app)
            var steps = 0
            while !(pane.exists && pane.isHittable), steps < Constants.settingsSidebarRows {
                app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])
                steps += 1
            }
            pane.click()
        }

        // MARK: Browse

        func testAReadOnlyFolderOffersNoRenameOrDelete() {
            let app = launchApp()
            open(.teamLibrary, in: app)
            let handbook = text(UITestFixture.File.handbook.name, in: app)
            XCTAssertTrue(handbook.waitToAppear())
            openMenu({ handbook.rightClick() }, until: app.menuItems[L10n.Browse.open])
            for action in [L10n.Browse.actionRename, L10n.Browse.actionDelete, L10n.Trash.moveToTrash] {
                XCTAssertFalse(contextMenuOffers(action, in: app), "Nothing in a read only folder offers \(action)")
            }
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        }

        func testAnEmptyFolderShowsTheEmptyState() {
            let app = launchApp()
            open(.projects, in: app)
            open(.drafts, in: app)
            XCTAssertTrue(text(L10n.EmptyState.folderEmpty, in: app).waitToAppear(), "An empty folder says so")
        }

        func testFoldersFourDeepOpenAndEnclosingWalksBackUp() {
            let app = launchApp()
            open(.projects, in: app)
            for folder in Folder.nestedChain {
                open(folder, in: app)
            }
            XCTAssertTrue(text(UITestFixture.File.agenda.name, in: app).waitToAppear())
            for parent in ([Folder.projects] + Folder.nestedChain.dropLast()).reversed() {
                app.typeKey(XCUIKeyboardKey.upArrow, modifierFlags: .command)
                XCTAssertTrue(windowTitled(parent.name, in: app).waitToAppear(), "⌘↑ lands on \(parent)")
            }
        }

        func testAnEmptyBrowseAreaSaysSo() {
            let app = launchApp(empty: [.browse])
            XCTAssertTrue(text(L10n.EmptyState.folderEmpty, in: app).waitToAppear())
        }

        func testABrowseAreaThatFailsSaysSo() {
            let app = launchApp(failing: [.browse])
            XCTAssertTrue(shows(L10n.Error.network, in: app).waitToAppear())
        }

        // MARK: Trash

        func testTheTrashSectionListsEverySeededState() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            sidebarItem(L10n.Trash.title, in: app).click()
            for entry in Entry.allCases {
                XCTAssertTrue(text(entry.name, in: app).waitToAppear(), "\(entry) is in the trash")
            }
            XCTAssertTrue(shows(Entry.otherPerson.displayName, in: app).exists, "One was deleted by someone else")
            XCTAssertTrue(shows(L10n.Trash.deletedByShareLink, in: app).exists, "One came in through a link")
        }

        func testAnEmptyTrashSectionSaysSo() {
            let app = launchApp(empty: [.trash])
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            sidebarItem(L10n.Trash.title, in: app).click()
            XCTAssertTrue(text(L10n.Trash.emptyState, in: app).waitToAppear())
        }

        func testATrashSectionThatFailsSaysSo() {
            let app = launchApp(failing: [.trash])
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            sidebarItem(L10n.Trash.title, in: app).click()
            XCTAssertTrue(shows(L10n.Trash.loadFailed, in: app).waitToAppear())
        }

        // MARK: Favorites

        func testTheFavoritesSectionShowsLabelsAndNestedNames() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            sidebarItem(L10n.Tab.favorites, in: app).click()
            XCTAssertTrue(shows(UITestFixture.FavoriteLabel.invoices.rawValue, in: app).waitToAppear())
            XCTAssertTrue(shows(UITestFixture.FavoriteLabel.teamLibrary.rawValue, in: app).exists)
            XCTAssertTrue(shows(Folder.website.name, in: app).exists)
        }

        func testFavoritesThatFailToLoadSaySo() {
            let app = launchApp(failing: [.favorites])
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            sidebarItem(L10n.Tab.favorites, in: app).click()
            XCTAssertTrue(shows(L10n.Error.network, in: app).waitToAppear())
        }

        // MARK: Admin

        func testTheUsersPaneListsEveryKindOfPerson() {
            let app = launchApp()
            openSettingsPane(L10n.Settings.rowUserManagement, in: app)
            for person in Person.allCases {
                XCTAssertTrue(shows(person.displayName, in: app).waitToAppear(), "\(person) is listed")
            }
        }

        func testAUsersPaneThatFailsSaysSo() {
            let app = launchApp(failing: [.users])
            openSettingsPane(L10n.Settings.rowUserManagement, in: app)
            XCTAssertTrue(shows(L10n.Error.network, in: app).waitToAppear())
        }

        func testTheActivityPaneListsItsLinesAndAnEmptyOneSaysSo() {
            let app = launchApp()
            openSettingsPane(L10n.ActivityLog.navigationTitle, in: app)
            XCTAssertTrue(shows(Person.jamie.username, in: app).waitToAppear(), "A line names who acted")
            app.terminate()

            let empty = launchApp(empty: [.activity])
            openSettingsPane(L10n.ActivityLog.navigationTitle, in: empty)
            XCTAssertTrue(shows(L10n.ActivityLog.none, in: empty).waitToAppear())
        }

        func testTheVersionsPaneListsEveryFileWithAHistory() {
            let app = launchApp()
            openSettingsPane(L10n.VersionedFiles.navigationTitle, in: app)
            // The main window behind lists some of the same names, so look only in the Settings window.
            let pane = app.windows.containing(NSPredicate(
                format: "value == %@",
                L10n.Settings.sectionGeneral
            )).firstMatch
            var previous: XCUIElement?
            for file in UITestFixture.VersionedFile.allCases {
                // Each file is one disclosure button whose label joins its name and facts.
                let row = pane.buttons.showingPart(file.file.name)
                // Rows below the fold of a short window come in on scroll: scroll from the row above.
                if let previous, !row.appears(within: UITestTimeout.short) {
                    previous.scroll(byDeltaX: 0, deltaY: -Self.macScrollStep)
                }
                XCTAssertTrue(row.waitToAppear(), "\(file) is listed")
                previous = row
            }
        }

        func testTheAccessRulesPaneListsEachRuleAndAnEmptyOneSaysSo() {
            let app = launchApp()
            openSettingsPane(L10n.Settings.rowAccessRules, in: app)
            for rule in UITestFixture.AccessRulePath.allCases {
                XCTAssertTrue(app.textFields.showingPart(rule.rawValue).waitToAppear(), "\(rule) is listed")
            }
            app.terminate()

            let empty = launchApp(empty: [.accessRules])
            openSettingsPane(L10n.Settings.rowAccessRules, in: empty)
            XCTAssertTrue(shows(L10n.AccessRules.empty, in: empty).waitToAppear())
        }
    }
#endif
