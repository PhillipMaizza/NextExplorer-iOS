#if os(macOS)
    import CoreModels
    import Localization
    import XCTest

    /// The Mac search panel, opened from the toolbar's search icon, ⌘F or ⌘K, and the toolbar refresh.
    final class MacSearchUITests: MacUITestCase {
        private func panelField(in app: XCUIApplication) -> XCUIElement {
            app.textFields[AccessibilityIdentifiers.Search.spotlightField]
        }

        func testToolbarSearchIconOpensThePanel() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())

            app.buttons[AccessibilityIdentifiers.Search.field].firstMatch.click()

            XCTAssertTrue(panelField(in: app).waitToAppear(), "The search icon should open the search panel")
            XCTAssertFalse(app.textFields[AccessibilityIdentifiers.Search.field].exists, "No inline search field")
        }

        /// A pushed folder keeps the search icon in its toolbar, and it opens the panel.
        func testSearchIconStaysInsideAFolder() {
            let app = launchApp()
            openDocuments(in: app)
            XCTAssertTrue(backButton(in: app).waitToAppear())

            let icon = app.buttons[AccessibilityIdentifiers.Search.field].firstMatch
            XCTAssertTrue(icon.waitToAppear(), "A folder's toolbar should show the search icon")
            icon.click()
            XCTAssertTrue(panelField(in: app).waitToAppear())
        }

        func testFindOpensThePanelAndTypingSearches() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            focusWindow(app)

            app.typeKey(Constants.findKey, modifierFlags: .command)
            XCTAssertTrue(panelField(in: app).isFocused(within: UITestTimeout.standard), "⌘F should open the panel")
            app.typeText(Fixture.searchQuery)
            XCTAssertTrue(searchHit(in: app).waitToAppear(), "Typing should show the search results")
        }

        /// Typing in the panel, letting the search run between keys, keeps every keystroke in the field.
        func testTypingInThePanelKeepsTheFieldFocused() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            focusWindow(app)
            app.typeKey(Constants.findKey, modifierFlags: .command)
            let field = panelField(in: app)
            XCTAssertTrue(field.waitToAppear())

            for (typed, character) in Fixture.folderAlt.enumerated() {
                app.typeText(String(character))
                if typed + 1 >= Fixture.minimumSearchLength {
                    XCTAssertTrue(searchHit(in: app).waitToAppear(), "Each partial query should run")
                }
            }
            XCTAssertTrue(field.isFocused(within: UITestTimeout.short), "The field should keep focus while typing")
            XCTAssertEqual(field.value as? String, Fixture.folderAlt, "Every keystroke should land in the field")
        }

        /// A folder found by search opens and loads like one opened from the table, and the panel goes.
        func testOpeningAFolderFromSearchLoadsIt() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            focusWindow(app)
            app.typeKey(Constants.findKey, modifierFlags: .command)
            app.typeText(Fixture.folderAlt)

            let hit = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", Fixture.folderAlt)).firstMatch
            XCTAssertTrue(hit.waitToAppear(), "The folder should be among the results")
            hit.click()

            XCTAssertTrue(panelField(in: app).waitToVanish(), "Choosing a result should close the panel")
            XCTAssertTrue(backButton(in: app).waitToAppear(), "Opening the result should push the folder")
            XCTAssertTrue(
                text(Fixture.file, in: app).waitToAppear(),
                "The opened folder should load its files, not stay on the skeleton"
            )
        }

        /// A file found by search opens the folder that holds it, loaded, from another folder.
        func testOpeningAFileFromSearchShowsItsFolder() {
            let app = launchApp()
            openDocuments(in: app)
            app.typeKey(Constants.findKey, modifierFlags: .command)
            app.typeText(Fixture.fileSearchTerm)

            let hit = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", Fixture.file)).firstMatch
            XCTAssertTrue(hit.waitToAppear(), "The file should be among the results")
            hit.click()

            XCTAssertTrue(panelField(in: app).waitToVanish(), "Choosing a result should close the panel")
            XCTAssertTrue(backButton(in: app).waitToVanish(), "Its folder (the root) should open")
            XCTAssertTrue(
                text(Fixture.folder, in: app).waitToAppear(),
                "The folder's listing should show, not a skeleton"
            )
        }

        func testRefreshShortcutConfirmsTheSync() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            focusWindow(app)

            app.typeKey(Constants.refreshKey, modifierFlags: .command)
            XCTAssertTrue(text(L10n.Common.syncCompleted, in: app).waitToAppear(), "⌘R should refresh and confirm it")
        }
    }
#endif
