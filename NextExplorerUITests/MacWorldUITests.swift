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

        private func open(_ folder: Folder, in app: XCUIApplication) {
            let row = text(folder.name, in: app)
            XCTAssertTrue(row.waitToAppear(), "\(folder) is listed")
            row.waitToBeHittable()
            openMenu({ row.doubleClick() }, until: windowTitled(folder.name, in: app))
        }

        private func shows(_ part: String, in app: XCUIApplication) -> XCUIElement {
            app.staticTexts.showingPart(part)
        }

        /// The Settings window on one of its panes, picked in its sidebar.
        private func openSettingsPane(_ title: String, in app: XCUIApplication) {
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            let pane = app.windows.descendants(matching: .any).titled(title)
            openSettingsWindow(in: app, until: pane)
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
                let item = app.menuItems[action]
                XCTAssertFalse(item.exists && item.isEnabled, "Nothing in a read only folder offers \(action)")
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
            for file in UITestFixture.VersionedFile.allCases {
                XCTAssertTrue(shows(file.file.name, in: app).waitToAppear(), "\(file) is listed")
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
