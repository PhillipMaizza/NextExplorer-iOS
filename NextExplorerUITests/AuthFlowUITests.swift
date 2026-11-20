#if os(iOS)
    import XCTest

    /// Critical path: the authentication lifecycle against the mocked auth client. Cold launch
    /// without a session, a rejected restore and sign out are also covered by the app reducer's tests.
    final class AuthFlowUITests: UITestCase {
        /// A restored session lands in the app and signs out to login; signing back in offers the
        /// sign in log only once a sign in fails, and the right password then reveals the app.
        func testASessionSignsOutAndSignsBackInAfterAFailure() {
            let app = launchApp(auth: .loggedIn)
            let settings = SettingsScreen(app: app)
            XCTAssertTrue(
                TabBar(app: app).browse.waitToAppear(),
                "A valid restored session should land on the Browse tab"
            )
            selectTab(TabBar(app: app).settings, until: settings.root)
            settings.revealSignOut()
            XCTAssertTrue(settings.signOutButton.waitToAppear(), "Expanding the account should reveal Sign Out")
            settings.signOutButton.tap()
            XCTAssertTrue(settings.confirmSignOut.waitToAppear(), "Sign out should present a confirmation sheet")
            settings.confirmSignOut.tap()

            let login = LoginScreen(app: app)
            login.enterServer()
            XCTAssertFalse(login.diagnosticsButton.appears(), "The sign in log stays hidden until something fails")
            login.submitCredentials(identifier: Fixture.rejectedIdentifier, password: Fixture.wrongPassword)
            XCTAssertTrue(
                login.diagnosticsButton.waitToAppear(),
                "A refused sign in should offer the sign in log at the bottom of the page"
            )

            login.submitCredentials()
            XCTAssertTrue(TabBar(app: app).browse.waitToAppear(), "A successful login should reveal the app")
        }

        func testExpiredRestoredSessionFallsBackToLogin() {
            let app = launchApp(auth: .expired)
            XCTAssertTrue(
                LoginScreen(app: app).hostField.waitToAppear(),
                "A server rejected session should fall back to login"
            )
        }
    }
#endif
