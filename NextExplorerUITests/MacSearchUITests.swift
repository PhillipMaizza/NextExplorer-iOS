#if os(macOS)
    import CoreModels
    import Localization
    import XCTest

    /// The top bar search field (⌘F), the search panel (⌘K), and the toolbar refresh.
    final class MacSearchUITests: MacUITestCase {
        private func panelField(in app: XCUIApplication) -> XCUIElement {
            app.textFields[AccessibilityIdentifiers.Search.spotlightField]
        }

        /// ⌘F focuses the top bar field, not the panel; typing searches in place and Escape clears it.
        func testFindFocusesTheTopBarFieldAndSearchesInPlace() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            focusWindow(app)
            app.typeKey(Constants.findKey, modifierFlags: .command)
            let field = app.textFields[AccessibilityIdentifiers.Search.field].firstMatch
            XCTAssertTrue(field.isFocused(within: UITestTimeout.standard), "⌘F should focus the top bar field")
            XCTAssertFalse(panelField(in: app).exists, "⌘F should not open the search panel")

            app.typeText(Fixture.folderAlt)
            XCTAssertTrue(searchHit(in: app).waitToAppear(), "The results should show in place")
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            XCTAssertTrue(searchHit(in: app).waitToVanish(), "Escape should clear the search")
        }

        /// ⌘K focuses the panel; typing, letting the search run between keys, keeps every keystroke,
        /// and a folder found opens and loads like one opened from the table.
        func testSpotlightTypesIntoThePanelAndOpensAFolderFound() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            focusWindow(app)
            app.typeKey(Constants.spotlightKey, modifierFlags: .command)
            let field = panelField(in: app)
            XCTAssertTrue(field.isFocused(within: UITestTimeout.standard), "⌘K should open the panel")

            for (typed, character) in Fixture.folderAlt.enumerated() {
                app.typeText(String(character))
                if typed + 1 >= Fixture.minimumSearchLength {
                    XCTAssertTrue(searchHit(in: app).waitToAppear(), "Each partial query should run")
                }
            }
            XCTAssertTrue(field.isFocused(within: UITestTimeout.short), "The field should keep focus while typing")
            XCTAssertEqual(field.value as? String, Fixture.folderAlt, "Every keystroke should land in the field")

            let hit = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", Fixture.folderAlt)).firstMatch
            XCTAssertTrue(hit.waitToAppear(), "The folder should be among the results")
            hit.click()
            XCTAssertTrue(field.waitToVanish(), "Choosing a result should close the panel")
            XCTAssertTrue(backButton(in: app).waitToAppear(), "Opening the result should push the folder")
            XCTAssertTrue(
                text(UITestFixture.Folder.cameraRoll.name, in: app).waitToAppear(),
                "The opened folder should load what it holds, not stay on the skeleton"
            )
        }

        /// A file found by search from another folder opens the folder that holds it, loaded, and ⌘R
        /// there refreshes and confirms it.
        func testAFileFoundOpensItsFolderAndRefreshConfirmsTheSync() {
            let app = launchApp()
            openDocuments(in: app)
            app.typeKey(Constants.spotlightKey, modifierFlags: .command)
            app.typeText(Fixture.fileSearchTerm)

            // The root copy, by the end of its row's label ("TXT, notes.txt, /"): the mocked tree also
            // has one in Documents, listed first as it sits in the folder on screen.
            let hit = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "\(Fixture.file), /")).firstMatch
            XCTAssertTrue(hit.waitToAppear(), "The file should be among the results")
            hit.click()
            XCTAssertTrue(panelField(in: app).waitToVanish(), "Choosing a result should close the panel")
            XCTAssertTrue(backButton(in: app).waitToVanish(), "Its folder (the root) should open")
            XCTAssertTrue(
                text(Fixture.folder, in: app).waitToAppear(),
                "The folder's listing should show, not a skeleton"
            )

            app.typeKey(Constants.refreshKey, modifierFlags: .command)
            XCTAssertTrue(text(L10n.Common.syncCompleted, in: app).waitToAppear(), "⌘R should refresh and confirm it")
        }
    }
#endif
