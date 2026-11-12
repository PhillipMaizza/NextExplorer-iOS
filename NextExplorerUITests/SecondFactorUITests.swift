#if os(iOS)
    import Localization
    import XCTest

    /// The second factor step of a password sign in: the six digit boxes that submit on the last
    /// digit, a wrong code, the recovery code alternative, and the sign in log that appears after
    /// a failure. Against the mocked auth client, which asks for a code when signing in as
    /// `Fixture.secondFactorIdentifier`.
    final class SecondFactorUITests: UITestCase {
        /// The iOS edit menu titles in the simulator's English locale.
        private static let selectAllTitle = "Select All"
        private static let copyTitle = "Copy"
        private static let pasteTitle = "Paste"

        private func reachCodePage() -> (app: XCUIApplication, login: LoginScreen) {
            let app = launchApp(auth: .loggedOut)
            let login = LoginScreen(app: app)
            login.signIn(identifier: Fixture.secondFactorIdentifier)

            XCTAssertTrue(login.codeField.waitToAppear(), "A right password on a 2FA account should open the code page, not an error")
            return (app, login)
        }

        func testLastDigitSignsIn() {
            let (app, login) = reachCodePage()
            login.codeField.tap()
            login.codeField.typeText(Fixture.validCode)

            XCTAssertTrue(TabBar(app: app).browse.waitToAppear(), "The sixth digit should sign in without a tap")
        }

        /// Copies text inside the app, so the system's "Allow Paste" prompt (cross app pasteboard
        /// access) never appears: type it into the recovery field, select it, copy it.
        func testPastedCodeFillsEveryBoxAndSignsIn() {
            let (app, login) = reachCodePage()
            login.codeModeButton.tap()
            login.codeField.clearAndType("123 456")
            login.codeField.press(forDuration: 1)
            XCTAssertTrue(app.menuItems[Self.selectAllTitle].waitToAppear())
            app.menuItems[Self.selectAllTitle].tap()
            XCTAssertTrue(app.menuItems[Self.copyTitle].waitToAppear())
            app.menuItems[Self.copyTitle].tap()

            login.codeModeButton.tap()
            login.codeField.press(forDuration: 1)
            XCTAssertTrue(app.menuItems[Self.pasteTitle].waitToAppear(), "The code field should offer Paste")
            app.menuItems[Self.pasteTitle].tap()

            XCTAssertTrue(TabBar(app: app).browse.waitToAppear(), "A pasted code with a space should fill the six boxes and sign in")
        }

        func testWrongCodeClearsTheBoxesAndShowsTheLog() {
            let (app, login) = reachCodePage()
            XCTAssertFalse(login.diagnosticsButton.appears(), "The sign in log stays hidden until something fails")

            login.codeField.tap()
            login.codeField.typeText(Fixture.wrongCode)

            XCTAssertTrue(login.diagnosticsButton.waitToAppear(), "A wrong code should offer the sign in log")
            XCTAssertEqual(login.codeField.value as? String ?? "", "", "A wrong code should be cleared, not left to erase digit by digit")

            XCTAssertTrue(app.keyboards.firstMatch.waitToAppear(), "The keyboard should come back after a wrong code, so the retry needs no extra tap")
            login.codeField.typeText(Fixture.validCode)
            XCTAssertTrue(TabBar(app: app).browse.waitToAppear(), "Retrying with the right code should sign in")
        }

        func testRecoveryCodeSignsInWithVerifyButton() {
            let (app, login) = reachCodePage()
            login.codeModeButton.tap()

            login.codeField.clearAndType(Fixture.validRecoveryCode)
            login.codeSubmitButton.tap()

            XCTAssertTrue(TabBar(app: app).browse.waitToAppear(), "A recovery code should sign in from the Verify button")
        }

        func testBackReturnsToPassword() {
            let (app, login) = reachCodePage()
            app.buttons[L10n.Common.back].tap()

            XCTAssertTrue(login.passwordField.waitToAppear(), "Back from the code page should return to the password page")
        }
    }
#endif
