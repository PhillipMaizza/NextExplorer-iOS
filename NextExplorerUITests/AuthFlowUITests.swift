#if os(iOS)
    import XCTest

    /// Critical path: the authentication lifecycle. Cold launch session restore (valid / expired),
    /// the full local login journey, and sign out, all against the mocked auth client.
    final class AuthFlowUITests: UITestCase {
        func testRestoredValidSessionLandsInApp() {
            let app = launchApp(auth: .loggedIn)
            XCTAssertTrue(
                TabBar(app: app).browse.waitToAppear(),
                "A valid restored session should land on the Browse tab"
            )
        }

        func testNoStoredSessionShowsLogin() {
            let app = launchApp(auth: .loggedOut)
            XCTAssertTrue(
                LoginScreen(app: app).hostField.waitToAppear(),
                "No stored session should show the server entry page"
            )
        }

        func testExpiredRestoredSessionFallsBackToLogin() {
            let app = launchApp(auth: .expired)
            XCTAssertTrue(
                LoginScreen(app: app).hostField.waitToAppear(),
                "A server rejected session should fall back to login"
            )
        }

        func testFullLocalLoginJourney() {
            let app = launchApp(auth: .loggedOut)
            LoginScreen(app: app).signIn()

            XCTAssertTrue(TabBar(app: app).browse.waitToAppear(), "A successful login should reveal the app")
        }

        func testSignOutReturnsToLogin() {
            let app = launchApp(auth: .loggedIn)
            let settings = SettingsScreen(app: app)
            selectTab(TabBar(app: app).settings, until: settings.addAccountRow)

            // Sign Out now lives inside the active account's collapsible section.
            XCTAssertTrue(settings.activeAccountRow.waitToAppear(), "Settings should show the active account")
            settings.activeAccountRow.tap()

            XCTAssertTrue(settings.signOutButton.waitToAppear(), "Expanding the account should reveal Sign Out")
            settings.signOutButton.tap()

            XCTAssertTrue(settings.confirmSignOut.waitToAppear(), "Sign out should present a confirmation sheet")
            settings.confirmSignOut.tap()

            XCTAssertTrue(LoginScreen(app: app).hostField.waitToAppear(), "Signing out should return to login")
        }

        func testSignInLogIsOfferedOnlyAfterAFailedSignIn() {
            let app = launchApp(auth: .loggedOut)
            let login = LoginScreen(app: app)
            login.enterServer()
            XCTAssertFalse(login.diagnosticsButton.appears(), "The sign in log stays hidden until something fails")

            login.submitCredentials(identifier: Fixture.rejectedIdentifier, password: Fixture.wrongPassword)

            XCTAssertTrue(
                login.diagnosticsButton.waitToAppear(),
                "A refused sign in should offer the sign in log at the bottom of the page"
            )
        }
    }
#endif
