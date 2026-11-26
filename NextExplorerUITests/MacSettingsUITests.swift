#if os(macOS)
    import CoreModels
    import Localization
    import XCTest

    /// Shared links, the Settings window, About and the account menu on the Mac.
    final class MacSettingsUITests: MacUITestCase {
        /// The Settings window's toggles flip, and picking another language rebuilds the window in
        /// it, not only the main window.
        func testSettingsWindowToggleFlipsAndLanguageReachesIt() {
            LocalizationOverride.apply(Constants.otherLanguage)
            let germanAppearance = L10n.Settings.rowAppearance
            LocalizationOverride.apply(nil)
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            let filesPane = app.windows.descendants(matching: .any).titled(L10n.Settings.sectionFiles)
            openSettingsWindow(in: app, until: filesPane)
            filesPane.click()
            let toggle = app.descendants(matching: .any)
                .matching(NSPredicate(
                    format: "(elementType == %d OR elementType == %d) AND label == %@",
                    XCUIElement.ElementType.switch.rawValue,
                    XCUIElement.ElementType.checkBox.rawValue,
                    L10n.Settings.toggleShowHiddenFiles
                ))
                .firstMatch
            XCTAssertTrue(toggle.waitToAppear())
            let before = toggle.value as? Int
            toggle.click()
            let flipped = NSPredicate(format: "value != %@", NSNumber(value: before ?? 0))
            XCTAssertTrue(waitUntil(flipped, on: toggle), "Clicking should flip the toggle")

            app.windows.descendants(matching: .any).titled(L10n.Settings.rowAppearance).click()
            let languages = app.scrollViews[AccessibilityIdentifiers.Settings.languagePicker]
            XCTAssertTrue(languages.waitToAppear())
            let german = languages.buttons[LocalizationOverride.displayName(for: Constants.otherLanguage)]
            XCTAssertTrue(german.waitToAppear())
            if !german.isHittable {
                languages.scroll(byDeltaX: 0, deltaY: -Constants.languageScroll)
            }
            german.click()
            XCTAssertTrue(
                text(germanAppearance, in: app).waitToAppear(),
                "The Settings window should switch to the new language"
            )
        }

        /// The licenses sheet in About closes with Esc like any Mac dialog.
        func testEscClosesTheLicensesSheet() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            focusWindow(app)
            app.menuBars.menuItems.titled(L10n.Menu.about).click()
            // A link styled button: AppKit may expose it as a link rather than a button.
            let licenses = app.windows.descendants(matching: .any).titled(L10n.Settings.rowOpenSourceLicenses)
            XCTAssertTrue(licenses.waitToAppear(), "About should offer the licenses")
            licenses.click()
            let sheet = app.sheets.firstMatch
            XCTAssertTrue(sheet.waitToAppear(), "Licenses should open as a sheet")
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            XCTAssertTrue(sheet.waitToVanish(), "Esc should close the licenses")
        }

        func testSignOutFromTheAccountMenu() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())

            let accounts = app.labeledButton(L10n.Settings.sectionAccounts)
            let signOut = app.labeledButton(L10n.Settings.signOutButton)
            openMenu({ accounts.click() }, until: signOut)
            signOut.click()

            let confirm = app.buttons[AccessibilityIdentifiers.Alert.confirm].firstMatch
            XCTAssertTrue(confirm.waitToAppear(), "Sign out should ask for confirmation")
            confirm.click()

            XCTAssertTrue(LoginScreen(app: app).hostField.waitToAppear(), "Signing out should return to login")
        }
    }
#endif
