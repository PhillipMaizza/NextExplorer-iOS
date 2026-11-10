#if os(iOS)
    import Localization
    import XCTest

    /// Making, renaming and revoking API tokens from Settings, against the mocked files client that
    /// keeps the account's tokens in memory and accepts `Fixture.accountPassword`.
    final class APITokensUITests: UITestCase {
        private static let tokenName = "backup script"

        private func openTokens() -> APITokensScreen {
            let app = launchApp(auth: .loggedIn)
            let settings = SettingsScreen(app: app)
            let screen = APITokensScreen(app: app)
            selectTab(TabBar(app: app).settings, until: settings.addAccountRow)

            XCTAssertTrue(scrollTo(screen.row, in: app), "API Tokens should be its own row in Settings, not hidden in the account")
            screen.row.tap()
            XCTAssertTrue(screen.emptyTitle.waitToAppear(), "An account with no tokens should open on the empty state")
            return screen
        }

        private func makeToken(_ screen: APITokensScreen, password: String = UITestCase.Fixture.accountPassword) {
            screen.newButton.tap()
            XCTAssertTrue(screen.nameField.waitToAppear(), "New Token should open the form")
            screen.nameField.tap()
            screen.nameField.typeText(Self.tokenName)
            XCTAssertFalse(screen.createButton.isEnabled, "Create stays off until the password is typed")
            screen.passwordField.tap()
            screen.passwordField.typeText(password)
            XCTAssertTrue(screen.createButton.isEnabled)
            screen.createButton.tap()
        }

        func testMakingATokenShowsTheSecretOnceThenListsIt() {
            let screen = openTokens()
            makeToken(screen)

            XCTAssertTrue(screen.issuedTitle.waitToAppear(), "A new token should show its secret")
            XCTAssertTrue(screen.copyButton.exists, "The secret should offer Copy")
            screen.issuedDoneButton.tap()

            XCTAssertTrue(screen.token(named: Self.tokenName).waitToAppear(), "The new token should be in the list")
            XCTAssertFalse(screen.emptyTitle.appears(), "The empty state should be gone")
        }

        func testAWrongPasswordShowsTheMessageAndMakesNothing() {
            let screen = openTokens()
            makeToken(screen, password: UITestCase.Fixture.wrongPassword)

            XCTAssertTrue(screen.wrongPasswordMessage.waitToAppear(), "A wrong password should show the server's message")
            XCTAssertFalse(screen.issuedTitle.appears(), "A wrong password must not make a token")
        }

        func testRenamingATokenChangesItsName() {
            let screen = openTokens()
            makeToken(screen)
            XCTAssertTrue(screen.issuedTitle.waitToAppear())
            screen.issuedDoneButton.tap()
            XCTAssertTrue(screen.menu(for: Self.tokenName).waitToAppear())

            screen.menu(for: Self.tokenName).tap()
            screen.renameAction.tap()
            XCTAssertTrue(screen.renameField.waitToAppear(), "Rename should ask for a new name")
            screen.renameField.clearAndType("nightly")
            screen.renameSaveButton.tap()

            XCTAssertTrue(screen.token(named: "nightly").waitToAppear(), "The token should show its new name")
            XCTAssertFalse(screen.token(named: Self.tokenName).appears(), "The old name should be gone")
        }

        func testRevokingATokenAsksFirstThenRemovesIt() {
            let screen = openTokens()
            makeToken(screen)
            XCTAssertTrue(screen.issuedTitle.waitToAppear())
            screen.issuedDoneButton.tap()
            XCTAssertTrue(screen.menu(for: Self.tokenName).waitToAppear())

            screen.menu(for: Self.tokenName).tap()
            screen.revokeAction.tap()
            XCTAssertTrue(screen.revokeConfirmButton.waitToAppear(), "Revoke should ask before it acts")
            screen.revokeConfirmButton.tap()

            XCTAssertTrue(screen.emptyTitle.waitToAppear(), "Revoking the only token should bring back the empty state")
            XCTAssertFalse(screen.token(named: Self.tokenName).appears())
        }
    }
#endif
