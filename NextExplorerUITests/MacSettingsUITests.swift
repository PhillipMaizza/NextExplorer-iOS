#if os(macOS)
    import CoreModels
    import Localization
    import XCTest

    /// Shared links, the Settings window, About and the account menu on the Mac.
    final class MacSettingsUITests: MacUITestCase {
        func testSharedSegmentsAndEditFromTheContextMenu() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            focusWindow(app)
            sidebarItem(L10n.Tab.shared, in: app).click()
            XCTAssertTrue(text(Self.byMeShare, in: app).waitToAppear())

            segment(L10n.Shared.segmentWithMe, in: app).click()
            XCTAssertTrue(text(Self.withMeShare, in: app).waitToAppear(), "With me should list links shared with me")

            segment(L10n.Shared.segmentByMe, in: app).click()
            XCTAssertTrue(text(Self.byMeShare, in: app).waitToAppear())
            text(Self.byMeShare, in: app).rightClick()
            XCTAssertTrue(app.menuItems[L10n.Common.edit].waitToAppear(), "A share I own should offer Edit")
            app.menuItems[L10n.Common.edit].click()

            XCTAssertTrue(text(L10n.EditShare.title, in: app).waitToAppear(), "Edit should open the edit share sheet")
        }

        func testSettingsWindowToggleFlips() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            let toggle = app.descendants(matching: .any)
                .matching(NSPredicate(format: "(elementType == %d OR elementType == %d) AND label == %@",
                                      XCUIElement.ElementType.switch.rawValue,
                                      XCUIElement.ElementType.checkBox.rawValue,
                                      L10n.Settings.toggleShowHiddenFiles))
                .firstMatch
            openSettingsWindow(in: app, until: toggle)
            let before = toggle.value as? Int
            toggle.click()

            let flipped = NSPredicate(format: "value != %@", NSNumber(value: before ?? 0))
            XCTAssertTrue(waitUntil(flipped, on: toggle), "Clicking should flip the toggle")
        }

        /// Picking another language in Settings rebuilds the Settings window in it, not only
        /// the main window.
        func testLanguageChangeReachesTheSettingsWindow() {
            LocalizationOverride.apply(Constants.otherLanguage)
            let germanGeneral = L10n.Settings.sectionGeneral
            LocalizationOverride.apply(nil)
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            let picker = app.popUpButtons[AccessibilityIdentifiers.Settings.languagePicker]
            openSettingsWindow(in: app, until: picker)
            picker.click()
            let german = app.menuItems[LocalizationOverride.displayName(for: Constants.otherLanguage)]
            XCTAssertTrue(german.waitToAppear())
            german.click()
            XCTAssertTrue(text(germanGeneral, in: app).waitToAppear(), "The Settings window should switch to the new language")
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

            let confirm = app.labeledButton(L10n.Common.logOut)
            XCTAssertTrue(confirm.waitToAppear(), "Sign out should ask for confirmation")
            confirm.click()

            XCTAssertTrue(LoginScreen(app: app).hostField.waitToAppear(), "Signing out should return to login")
        }
    }
#endif
