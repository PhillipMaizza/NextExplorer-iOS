#if os(iOS)
    import XCTest

    /// Critical path: the multi server account switcher in Settings. Presence of the switcher, opening
    /// the add account login sheet, and adding a second server so it appears alongside the first: all
    /// against the stateful mocked auth client.
    final class MultiServerUITests: UITestCase {
        func testSwitcherShowsActiveAccountAndAddRow() {
            let app = launchApp(auth: .loggedIn)
            let settings = SettingsScreen(app: app)
            selectTab(TabBar(app: app).settings, until: settings.addAccountRow)

            XCTAssertTrue(settings.accountsSectionHeader.waitToAppear(), "Settings should show an Accounts section")
            XCTAssertTrue(settings.addAccountRow.exists, "The switcher should offer an Add Account row")
            XCTAssertTrue(settings.accountRow(host: Fixture.serverHost).exists, "The active account should be listed")
        }

        func testAddingSecondServerListsBothAccounts() {
            let app = launchApp(auth: .loggedIn)
            let settings = SettingsScreen(app: app)
            selectTab(TabBar(app: app).settings, until: settings.addAccountRow)

            XCTAssertTrue(settings.addAccountRow.waitToAppear())
            settings.addAccountRow.tap()

            LoginScreen(app: app).signIn(host: Fixture.otherServerHost)

            // Adding a server adopts it as active and remounts the app on the new account.
            XCTAssertTrue(TabBar(app: app).browse.waitToAppear(), "Adding an account should reveal the app on the new account")

            selectTab(TabBar(app: app).settings, until: settings.addAccountRow)
            XCTAssertTrue(settings.accountRow(host: Fixture.otherServerHost).waitToAppear(), "The newly added server should be listed")
            XCTAssertTrue(settings.accountRow(host: Fixture.serverHost).exists, "The original account should still be listed")
        }
    }
#endif
