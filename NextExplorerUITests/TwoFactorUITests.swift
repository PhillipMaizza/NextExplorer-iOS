#if os(iOS)
    import Localization
    import XCTest

    /// Turning two-factor authentication on and off from Settings, against the mocked files client
    /// that keeps the account's second factor in memory and accepts `Fixture.validCode` and
    /// `Fixture.accountPassword`.
    final class TwoFactorUITests: UITestCase {
        private func openTwoFactor() -> (app: XCUIApplication, screen: TwoFactorScreen) {
            let app = launchApp(auth: .loggedIn)
            let settings = SettingsScreen(app: app)
            let screen = TwoFactorScreen(app: app)
            selectTab(TabBar(app: app).settings, until: settings.addAccountRow)

            XCTAssertTrue(
                screen.row.waitToAppear(),
                "The Two-Factor row should be visible without expanding the account"
            )
            screen.row.tap()
            XCTAssertTrue(
                screen.offTitle.waitToAppear(),
                "An account without a second factor should open on the off screen"
            )
            return (app, screen)
        }

        private func turnOn(_ screen: TwoFactorScreen) {
            screen.turnOnButton.tap()
            XCTAssertTrue(screen.setupKey.waitToAppear(), "Turning on should show the setup key")
            XCTAssertTrue(screen.codeField.waitToAppear(), "Turning on should show the code boxes")
            screen.codeField.tap()
            screen.codeField.typeText(UITestCase.Fixture.validCode)
            XCTAssertTrue(
                screen.recoveryTitle.waitToAppear(),
                "The sixth digit should confirm and show the recovery codes"
            )
        }

        func testTurningOnShowsTheRecoveryCodesThenLandsOnOn() {
            let (_, screen) = openTwoFactor()
            turnOn(screen)

            screen.recoveryDoneButton.tap()
            XCTAssertTrue(screen.onTitle.waitToAppear(), "Done should land on the on screen")
        }

        func testAWrongCodeShowsTheMessageAndClearsTheBoxes() {
            let (_, screen) = openTwoFactor()
            screen.turnOnButton.tap()
            XCTAssertTrue(screen.codeField.waitToAppear())
            screen.codeField.tap()
            screen.codeField.typeText(UITestCase.Fixture.wrongCode)

            XCTAssertTrue(screen.wrongCodeMessage.waitToAppear(), "A wrong code should show the server's message")
            XCTAssertFalse(screen.recoveryTitle.appears(), "A wrong code must not turn it on")
            XCTAssertEqual(
                screen.codeField.value as? String ?? "",
                "",
                "A wrong code should be cleared so it can be typed again"
            )
        }

        func testTurningOffAsksForThePasswordAndAWrongOneKeepsItOn() {
            let (_, screen) = openTwoFactor()
            turnOn(screen)
            screen.recoveryDoneButton.tap()
            XCTAssertTrue(screen.onTitle.waitToAppear())

            screen.turnOffButton.tap()
            XCTAssertTrue(screen.passwordField.waitToAppear(), "Turning off should ask for the password")
            screen.passwordField.tap()
            screen.passwordField.typeText(UITestCase.Fixture.wrongPassword)
            screen.passwordConfirmButton.tap()
            XCTAssertTrue(
                screen.wrongPasswordMessage.waitToAppear(),
                "A wrong password should show the server's message"
            )
            XCTAssertTrue(screen.onTitle.exists, "A wrong password must leave it on")

            screen.passwordField.clearAndType(UITestCase.Fixture.accountPassword)
            screen.passwordConfirmButton.tap()
            XCTAssertTrue(screen.offTitle.waitToAppear(), "The right password should turn it off")
        }

        func testNewRecoveryCodesAreShownAfterThePassword() {
            let (_, screen) = openTwoFactor()
            turnOn(screen)
            screen.recoveryDoneButton.tap()
            XCTAssertTrue(screen.onTitle.waitToAppear())

            screen.newCodesButton.tap()
            XCTAssertTrue(screen.passwordField.waitToAppear())
            screen.passwordField.tap()
            screen.passwordField.typeText(UITestCase.Fixture.accountPassword)
            screen.passwordConfirmButton.tap()
            XCTAssertTrue(screen.recoveryTitle.waitToAppear(), "The right password should show the new recovery codes")
        }
    }
#endif
