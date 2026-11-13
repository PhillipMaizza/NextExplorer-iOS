#if os(macOS)
    import CoreModels
    import Localization
    import XCTest

    /// Base of the Mac XCUITest suites: the critical paths of the Mac app against the same mocked
    /// backend as the iOS suites. Runs on the Mac itself, so it drives the real pointer and keyboard
    /// while it runs. Holds the Mac only locators, constants and flows the suites share.
    class MacUITestCase: UITestCase {
        enum Constants {
            /// AppKit's own menu names (the suite runs in English).
            static let fileMenu = "File"
            static let viewMenu = "View"
            /// What the file tests name a new folder and rename a file to.
            static let newFolderName = "Reports"
            static let renamedFile = "todo.txt"
            /// A language other than English, for the live language switch.
            static let otherLanguage = "de"
            /// Shortcut keys: ⌘F search, ⌘R refresh, ⇧⌘G go to folder, ⌘, settings.
            static let findKey = "f"
            static let refreshKey = "r"
            static let goToFolderKey = "g"
            static let settingsKey = ","
            /// Part of `Fixture.file`'s name, so it is among the search results.
            static let fileSearchTerm = "notes"
        }

        /// A by me link and the with me link in the mocked shares.
        static let byMeShare = "Electricity"
        static let withMeShare = "Team Roadmap"

        /// Text on screen, matched by label or value: table cells expose their text as a value.
        func text(_ string: String, in app: XCUIApplication) -> XCUIElement {
            app.staticTexts.showing(string)
        }

        /// The mocked search's fixed hit. A result row carries its name on the row itself rather
        /// than a separate text.
        func searchHit(in app: XCUIApplication) -> XCUIElement {
            app.descendants(matching: .any)
                .matching(NSPredicate(
                    format: "label CONTAINS %@ OR value CONTAINS %@",
                    Fixture.searchHit,
                    Fixture.searchHit
                ))
                .firstMatch
        }

        /// A section in the main window's sidebar, a native selectable list row on the Mac.
        func sidebarItem(_ title: String, in app: XCUIApplication) -> XCUIElement {
            app.outlines.cells.staticTexts.showing(title)
        }

        /// An item of the Go menu, opened first.
        func goMenuItem(_ title: String, in app: XCUIApplication) -> XCUIElement {
            app.menuBars.menuBarItems[L10n.Menu.go].click()
            return app.menuBars.menuItems[title]
        }

        /// The main window once its title (the folder on screen) reads `title`.
        func windowTitled(_ title: String, in app: XCUIApplication) -> XCUIElement {
            app.windows.titled(title)
        }

        func backButton(in app: XCUIApplication) -> XCUIElement {
            app.toolbars.buttons.labeled(L10n.Common.back)
        }

        /// A segment of a native segmented control, which the Mac exposes as a radio button.
        func segment(_ title: String, in app: XCUIApplication) -> XCUIElement {
            app.radioButtons.titled(title)
        }

        /// Clicks into the table so the window is key: menu commands that act on the visible
        /// screen (⌘F, ⌘R) read it from the key window, which a fresh test launch may not have yet.
        /// Opens the Settings window (its own window on the Mac) with ⌘, until `sentinel` shows. A
        /// fresh launch can drop the first ⌘, while its menu bar is still settling, so the shared
        /// `openMenu` retries it once.
        func openSettingsWindow(in app: XCUIApplication, until sentinel: XCUIElement) {
            openMenu({
                focusWindow(app)
                app.typeKey(Constants.settingsKey, modifierFlags: .command)
            }, until: sentinel)
        }

        func focusWindow(_ app: XCUIApplication) {
            text(Fixture.folder, in: app).click()
        }

        func openDocuments(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
            let folder = text(Fixture.folder, in: app)
            XCTAssertTrue(folder.waitToAppear(file: file, line: line))
            folder.waitToBeHittable(file: file, line: line)
            // The table can still be rebuilding its rows right after launch, which drops the first
            // double click; one retry covers it.
            folder.doubleClick()
            if !backButton(in: app).appears(within: UITestTimeout.short) {
                text(Fixture.folder, in: app).doubleClick()
            }
            XCTAssertTrue(backButton(in: app).waitToAppear(
                UITestTimeout.standard,
                "Double click should open the folder",
                file: file,
                line: line
            ))
        }
    }
#endif
