#if os(macOS)
    import CoreModels
    import Localization
    import XCTest

    /// The Mac search panel, opened from the toolbar's search icon, ⌘F or ⌘K, and the toolbar refresh.
    final class MacSearchUITests: MacUITestCase {
        private func panelField(in app: XCUIApplication) -> XCUIElement {
            app.textFields[AccessibilityIdentifiers.Search.spotlightField]
        }

        /// The toolbar's search icon opens the panel, in a pushed folder and at the root, where there
        /// is no inline field.
        func testTheSearchIconOpensThePanelInAFolderAndAtTheRoot() {
            let app = launchApp()
            openDocuments(in: app)
            XCTAssertTrue(backButton(in: app).waitToAppear())
            let icon = app.buttons[AccessibilityIdentifiers.Search.field].firstMatch
            XCTAssertTrue(icon.waitToAppear(), "A folder's toolbar should show the search icon")
            icon.click()
            XCTAssertTrue(panelField(in: app).waitToAppear())
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            XCTAssertTrue(panelField(in: app).waitToVanish())

            backButton(in: app).click()
            XCTAssertTrue(backButton(in: app).waitToVanish())
            icon.click()
            XCTAssertTrue(panelField(in: app).waitToAppear(), "The search icon should open the search panel")
            XCTAssertFalse(app.textFields[AccessibilityIdentifiers.Search.field].exists, "No inline search field")
        }

        /// ⌘F focuses the panel; typing, letting the search run between keys, keeps every keystroke,
        /// and a folder found opens and loads like one opened from the table.
        func testFindTypesIntoThePanelAndOpensAFolderFound() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            focusWindow(app)
            app.typeKey(Constants.findKey, modifierFlags: .command)
            let field = panelField(in: app)
            XCTAssertTrue(field.isFocused(within: UITestTimeout.standard), "⌘F should open the panel")

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
            app.typeKey(Constants.findKey, modifierFlags: .command)
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
