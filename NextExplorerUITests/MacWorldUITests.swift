#if os(macOS)
    import CoreModels
    import Localization
    import XCTest

    /// The Mac against the mocked world's own states, matching the iPhone suites: the browse tree's
    /// read only, empty and deep folders, the seeded trash and favorites, and the admin panes. Browse
    /// keeps the UI check of an empty and a failing area; the other areas' empty and failed loads
    /// are covered by their reducers' tests.
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

        /// Picks a pane in the open Settings window's sidebar. Sidebar rows read their names as a
        /// value, and the lower ones only exist once scrolled to, so the arrow keys walk down from
        /// General, which is always in view.
        private func selectSettingsPane(_ title: String, in app: XCUIApplication) {
            text(L10n.Settings.sectionGeneral, in: app).click()
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

        /// An empty folder says so, and folders four deep open and ⌘↑ walks back up the chain.
        func testAnEmptyFolderAndFoldersFourDeepWalkBackUp() {
            let app = launchApp()
            open(.projects, in: app)
            open(.drafts, in: app)
            XCTAssertTrue(text(L10n.EmptyState.folderEmpty, in: app).waitToAppear(), "An empty folder says so")
            app.typeKey(XCUIKeyboardKey.upArrow, modifierFlags: .command)
            XCTAssertTrue(windowTitled(Folder.projects.name, in: app).waitToAppear())

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

        // MARK: Sidebar sections

        /// The trash lists one row per seeded state, and Favorites shows labels and nested names.
        func testTheTrashAndFavoritesSectionsListTheirSeededData() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            sidebarItem(L10n.Trash.title, in: app).click()
            for entry in Entry.allCases {
                XCTAssertTrue(text(entry.name, in: app).waitToAppear(), "\(entry) is in the trash")
            }
            XCTAssertTrue(shows(Entry.otherPerson.displayName, in: app).exists, "One was deleted by someone else")
            XCTAssertTrue(shows(L10n.Trash.deletedByShareLink, in: app).exists, "One came in through a link")

            sidebarItem(L10n.Tab.favorites, in: app).click()
            XCTAssertTrue(shows(UITestFixture.FavoriteLabel.invoices.rawValue, in: app).waitToAppear())
            XCTAssertTrue(shows(UITestFixture.FavoriteLabel.teamLibrary.rawValue, in: app).exists)
            XCTAssertTrue(shows(Folder.website.name, in: app).exists)
        }

        // MARK: Admin

        /// Every admin pane in one Settings window: Users, Activity, File Versions and Access Rules
        /// each list their seeded variety.
        func testTheAdminPanesListTheirSeededData() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            openSettingsWindow(in: app, until: text(L10n.Settings.sectionGeneral, in: app))
            // The main window behind lists some of the same names, so look only in the Settings window.
            let settings = app.windows.containing(NSPredicate(
                format: "value == %@",
                L10n.Settings.sectionGeneral
            )).firstMatch

            selectSettingsPane(L10n.Settings.rowUserManagement, in: app)
            for person in Person.allCases {
                XCTAssertTrue(shows(person.displayName, in: app).waitToAppear(), "\(person) is listed")
            }

            selectSettingsPane(L10n.ActivityLog.navigationTitle, in: app)
            XCTAssertTrue(shows(Person.jamie.username, in: app).waitToAppear(), "A line names who acted")

            selectSettingsPane(L10n.VersionedFiles.navigationTitle, in: app)
            var previous: XCUIElement?
            for file in UITestFixture.VersionedFile.allCases {
                // Each file is one disclosure button whose label joins its name and facts.
                let row = settings.buttons.showingPart(file.file.name)
                // Rows below the fold of a short window come in on scroll: scroll from the row above.
                if let previous, !row.appears(within: UITestTimeout.short) {
                    previous.scroll(byDeltaX: 0, deltaY: -Self.macScrollStep)
                }
                XCTAssertTrue(row.waitToAppear(), "\(file) is listed")
                previous = row
            }

            selectSettingsPane(L10n.Settings.rowAccessRules, in: app)
            for rule in UITestFixture.AccessRulePath.allCases {
                XCTAssertTrue(app.textFields.showingPart(rule.rawValue).waitToAppear(), "\(rule) is listed")
            }
        }
    }
#endif
