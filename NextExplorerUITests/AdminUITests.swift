#if os(iOS)
    import CoreModels
    import Localization
    import XCTest

    /// The admin pages against the mocked server, in one walk: each lists its seeded variety. Their
    /// empty and failed loads are covered by the reducers' tests; Browse keeps the UI check of both.
    final class AdminUITests: UITestCase {
        private typealias Person = UITestFixture.ManagedUser

        func testEveryAdminPageListsItsSeededData() {
            let app = launchApp()
            let settings = SettingsScreen(app: app)
            let admin = AdminScreen(app: app)
            let back = app.navigationBars.buttons.firstMatch

            selectTab(TabBar(app: app).settings, until: settings.root)
            XCTAssertTrue(scrollTo(settings.pageRow(.users), in: app))
            settings.pageRow(.users).tap()
            for person in Person.allCases {
                XCTAssertTrue(scrollTo(app.staticTexts.showingPart(person.displayName), in: app), "\(person) is listed")
            }
            back.tap()

            XCTAssertTrue(scrollTo(settings.pageRow(.administration), in: app))
            settings.pageRow(.administration).tap()

            open(L10n.ActivityLog.navigationTitle, on: admin, in: app)
            XCTAssertTrue(
                scrollTo(app.staticTexts.showingPart(Person.jamie.username), in: app),
                "The newest activity line names who acted"
            )
            back.tap()

            open(L10n.VersionedFiles.navigationTitle, on: admin, in: app)
            for file in UITestFixture.VersionedFile.allCases {
                XCTAssertTrue(scrollTo(app.staticTexts.showingPart(file.file.name), in: app), "\(file) is listed")
            }
            back.tap()

            open(L10n.Settings.rowAccessRules, on: admin, in: app)
            for rule in UITestFixture.AccessRulePath.allCases {
                XCTAssertTrue(scrollTo(app.textFields.showingPart(rule.rawValue), in: app), "\(rule) is listed")
            }
        }

        private func open(_ title: String, on admin: AdminScreen, in app: XCUIApplication) {
            XCTAssertTrue(scrollTo(admin.row(title), in: app), "The Admin page lists \(title)")
            admin.row(title).tap()
        }
    }
#endif
