#if os(iOS)
    import CoreModels
    import Localization
    import XCTest

    /// The admin pages against the mocked server: each lists its seeded variety, says so when it
    /// has nothing, and shows the error when its route fails.
    final class AdminUITests: UITestCase {
        private typealias Person = UITestFixture.ManagedUser

        private func openAdministration(_ app: XCUIApplication) {
            let settings = SettingsScreen(app: app)
            selectTab(TabBar(app: app).settings, until: settings.root)
            XCTAssertTrue(scrollTo(settings.pageRow(.administration), in: app))
            settings.pageRow(.administration).tap()
        }

        private func openUsers(_ app: XCUIApplication) {
            let settings = SettingsScreen(app: app)
            selectTab(TabBar(app: app).settings, until: settings.root)
            XCTAssertTrue(scrollTo(settings.pageRow(.users), in: app))
            settings.pageRow(.users).tap()
        }

        private func openAdminPage(_ title: String, in app: XCUIApplication) {
            openAdministration(app)
            let admin = AdminScreen(app: app)
            XCTAssertTrue(scrollTo(admin.row(title), in: app), "The Admin page lists \(title)")
            admin.row(title).tap()
        }

        func testUsersListEveryKindOfPerson() {
            let app = launchApp()
            openUsers(app)
            for person in Person.allCases {
                XCTAssertTrue(scrollTo(app.staticTexts.showingPart(person.displayName), in: app), "\(person) is listed")
            }
        }

        func testUsersWithOnlyTheSignedInAccountListJustThem() {
            let app = launchApp(empty: [.users])
            openUsers(app)
            XCTAssertTrue(app.staticTexts.showingPart(UITestFixture.SignedInAccount.username.rawValue)
                .waitToAppear())
            XCTAssertFalse(app.staticTexts.showingPart(Person.jamie.displayName).exists)
        }

        func testUsersThatFailToLoadSaySo() {
            let app = launchApp(failing: [.users])
            openUsers(app)
            XCTAssertTrue(AdminScreen(app: app).networkError.waitToAppear(), "A failed load shows the error")
        }

        func testTheActivityLogListsItsSeededLines() {
            let app = launchApp()
            openAdminPage(L10n.ActivityLog.navigationTitle, in: app)
            XCTAssertTrue(
                scrollTo(app.staticTexts.showingPart(Person.jamie.username), in: app),
                "The newest line names who acted"
            )
        }

        func testAnEmptyActivityLogSaysSo() {
            let app = launchApp(empty: [.activity])
            openAdminPage(L10n.ActivityLog.navigationTitle, in: app)
            XCTAssertTrue(scrollTo(AdminScreen(app: app).row(L10n.ActivityLog.none), in: app))
        }

        func testAnActivityLogThatFailsSaysSo() {
            let app = launchApp(failing: [.activity])
            openAdminPage(L10n.ActivityLog.navigationTitle, in: app)
            XCTAssertTrue(AdminScreen(app: app).networkError.waitToAppear())
        }

        func testVersionedFilesListEveryFileWithAHistory() {
            let app = launchApp()
            openAdminPage(L10n.VersionedFiles.navigationTitle, in: app)
            for file in UITestFixture.VersionedFile.allCases {
                XCTAssertTrue(scrollTo(app.staticTexts.showingPart(file.file.name), in: app), "\(file) is listed")
            }
        }

        func testNoVersionedFilesSaysSo() {
            let app = launchApp(empty: [.versions])
            openAdminPage(L10n.VersionedFiles.navigationTitle, in: app)
            XCTAssertTrue(AdminScreen(app: app).row(L10n.VersionedFiles.none).waitToAppear())
        }

        func testAccessRulesListEachRule() {
            let app = launchApp()
            openAdminPage(L10n.Settings.rowAccessRules, in: app)
            for rule in UITestFixture.AccessRulePath.allCases {
                XCTAssertTrue(scrollTo(app.textFields.showingPart(rule.rawValue), in: app), "\(rule) is listed")
            }
        }

        func testNoAccessRulesSaysSo() {
            let app = launchApp(empty: [.accessRules])
            openAdminPage(L10n.Settings.rowAccessRules, in: app)
            XCTAssertTrue(scrollTo(AdminScreen(app: app).row(L10n.AccessRules.empty), in: app))
        }

        func testAccessRulesThatFailToLoadSaySo() {
            let app = launchApp(failing: [.accessRules])
            openAdminPage(L10n.Settings.rowAccessRules, in: app)
            XCTAssertTrue(AdminScreen(app: app).networkError.waitToAppear())
        }
    }
#endif
