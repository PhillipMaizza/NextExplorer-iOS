import XCTest

/// Critical path: the authentication lifecycle. Cold launch session restore (valid / expired),
/// the full local login journey, and sign out, all against the mocked auth client.
final class AuthFlowUITests: UITestCase {
    func testRestoredValidSessionLandsInApp() {
        let app = launchApp(auth: .loggedIn)
        XCTAssertTrue(TabBar(app: app).browse.waitToAppear(), "A valid restored session should land on the Browse tab")
    }

    func testNoStoredSessionShowsLogin() {
        let app = launchApp(auth: .loggedOut)
        XCTAssertTrue(LoginScreen(app: app).hostField.waitToAppear(), "No stored session should show the server entry page")
    }

    func testExpiredRestoredSessionFallsBackToLogin() {
        let app = launchApp(auth: .expired)
        XCTAssertTrue(LoginScreen(app: app).hostField.waitToAppear(), "A server rejected session should fall back to login")
    }

    func testFullLocalLoginJourney() {
        let app = launchApp(auth: .loggedOut)
        let login = LoginScreen(app: app)

        XCTAssertTrue(login.hostField.waitToAppear())
        login.hostField.clearAndType("nextexplorer.example.com")

        login.testConnectionButton.tap()

        XCTAssertTrue(login.emailField.waitToAppear(), "Test connection should advance to the credentials page")
        login.emailField.clearAndType("phillip@example.com")

        XCTAssertTrue(login.passwordField.waitToAppear())
        login.passwordField.clearAndType("hunter2")

        login.submitButton.tap()

        XCTAssertTrue(TabBar(app: app).browse.waitToAppear(), "A successful login should reveal the app")
    }

    func testSignOutReturnsToLogin() {
        let app = launchApp(auth: .loggedIn)
        let settings = SettingsScreen(app: app)
        selectTab(TabBar(app: app).settings, until: settings.languageRow)

        XCTAssertTrue(settings.signOutButton.waitToAppear(), "Settings should expose a Sign Out button")
        settings.signOutButton.tap()

        XCTAssertTrue(settings.confirmSignOut.waitToAppear(), "Sign out should present a confirmation sheet")
        settings.confirmSignOut.tap()

        XCTAssertTrue(LoginScreen(app: app).hostField.waitToAppear(), "Signing out should return to login")
    }
}
