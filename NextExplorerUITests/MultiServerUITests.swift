import XCTest

/// Critical path: the multi-server account switcher in Settings. Presence of the switcher, opening
/// the add-account login sheet, and adding a second server so it appears alongside the first — all
/// against the stateful mocked auth client.
final class MultiServerUITests: UITestCase {
    func testSwitcherShowsActiveAccountAndAddRow() {
        let app = launchApp(auth: .loggedIn)
        let settings = SettingsScreen(app: app)
        selectTab(TabBar(app: app).settings, until: settings.signOutButton)

        XCTAssertTrue(settings.accountsSectionHeader.waitToAppear(), "Settings should show an Accounts section")
        XCTAssertTrue(settings.addAccountRow.exists, "The switcher should offer an Add Account row")
        XCTAssertTrue(settings.accountRow(host: "nextexplorer.example.com").exists, "The active account should be listed")
    }

    func testAddAccountOpensLoginSheet() {
        let app = launchApp(auth: .loggedIn)
        let settings = SettingsScreen(app: app)
        selectTab(TabBar(app: app).settings, until: settings.signOutButton)

        XCTAssertTrue(settings.addAccountRow.waitToAppear())
        settings.addAccountRow.tap()

        XCTAssertTrue(LoginScreen(app: app).hostField.waitToAppear(), "Add Account should present the login sheet")
    }

    func testAddingSecondServerListsBothAccounts() {
        let app = launchApp(auth: .loggedIn)
        let settings = SettingsScreen(app: app)
        selectTab(TabBar(app: app).settings, until: settings.signOutButton)

        XCTAssertTrue(settings.addAccountRow.waitToAppear())
        settings.addAccountRow.tap()

        let login = LoginScreen(app: app)
        XCTAssertTrue(login.hostField.waitToAppear())
        login.hostField.clearAndType("other.example.com")
        login.testConnectionButton.tap()

        XCTAssertTrue(login.emailField.waitToAppear(), "Test connection should advance to the credentials page")
        login.emailField.clearAndType("phillip@example.com")
        XCTAssertTrue(login.passwordField.waitToAppear())
        login.passwordField.clearAndType("hunter2")
        login.submitButton.tap()

        // Adding a server adopts it as active and remounts the app on the new account.
        XCTAssertTrue(TabBar(app: app).browse.waitToAppear(), "Adding an account should reveal the app on the new account")

        selectTab(TabBar(app: app).settings, until: settings.signOutButton)
        XCTAssertTrue(settings.accountRow(host: "other.example.com").waitToAppear(), "The newly added server should be listed")
        XCTAssertTrue(settings.accountRow(host: "nextexplorer.example.com").exists, "The original account should still be listed")
    }
}
