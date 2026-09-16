import XCTest

/// Critical path: a mid session 401. An authenticated request answering 401 trips the session
/// expiry path, which drops the app back to login and clears cached state.
final class SessionExpiryUITests: UITestCase {
    func testMidSessionExpiryReturnsToLogin() {
        // Launches authenticated, but the first browse answers 401.
        let app = launchApp(auth: .loggedIn, scenario: .sessionExpired)
        XCTAssertTrue(LoginScreen(app: app).hostField.waitToAppear(), "A mid session 401 should return to login")
    }
}
