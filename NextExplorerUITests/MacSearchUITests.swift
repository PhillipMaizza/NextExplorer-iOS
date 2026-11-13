#if os(macOS)
    import CoreModels
    import Localization
    import XCTest

    /// The toolbar search and refresh on the Mac.
    final class MacSearchUITests: MacUITestCase {
        /// A search result's Show in Enclosing Folder ends the search and opens where it lives.
        func testShowInEnclosingFolderFromSearch() {
            let app = launchApp()
            openDocuments(in: app)
            app.typeKey(Constants.findKey, modifierFlags: .command)
            app.typeText(Constants.fileSearchTerm)

            let hit = app.outlines.cells.staticTexts.showing(Fixture.file)
            XCTAssertTrue(hit.waitToAppear(), "The file should be among the search results")
            hit.rightClick()
            let show = app.menuItems[L10n.Browse.showInEnclosingFolder]
            XCTAssertTrue(show.waitToAppear(), "A search result should offer Show in Enclosing Folder")
            show.click()
            XCTAssertTrue(backButton(in: app).waitToVanish(), "Its folder (the root) should open")
            XCTAssertTrue(
                text(Fixture.folder, in: app).waitToAppear(),
                "The folder's listing should show, not search results"
            )
        }

        func testFindFocusesTheToolbarSearch() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            focusWindow(app)

            app.typeKey(Constants.findKey, modifierFlags: .command)
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.isFocused(within: UITestTimeout.standard), "⌘F should focus the toolbar search")
            app.typeText(Fixture.searchQuery)
            XCTAssertTrue(searchHit(in: app).waitToAppear(), "⌘F then typing should show the search results")
        }

        /// Typing in the toolbar search, letting the search run between keys, keeps every keystroke
        /// in the field.
        func testTypingInSearchKeepsTheFieldFocused() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            focusWindow(app)
            app.typeKey(Constants.findKey, modifierFlags: .command)
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitToAppear())

            for (typed, character) in Fixture.folderAlt.enumerated() {
                app.typeText(String(character))
                // From the server minimum on, each key resets the results to the instant matches and
                // the debounced search adds the hit back, so the hit showing again means this partial
                // query has run before the next key.
                if typed + 1 >= Fixture.minimumSearchLength {
                    XCTAssertTrue(searchHit(in: app).waitToAppear(), "Each partial query should run")
                }
            }
            XCTAssertTrue(
                field.isFocused(within: UITestTimeout.short),
                "The search field should keep focus while typing"
            )
            XCTAssertEqual(field.value as? String, Fixture.folderAlt, "Every keystroke should land in the search field")
        }

        /// A folder found by search opens and loads like one opened from the table.
        func testOpeningAFolderFromSearchLoadsIt() {
            let app = launchApp()
            XCTAssertTrue(text(Fixture.folder, in: app).waitToAppear())
            focusWindow(app)
            app.typeKey(Constants.findKey, modifierFlags: .command)
            app.typeText(Fixture.folderAlt)

            let hit = app.outlines.cells.staticTexts.showing(Fixture.folderAlt)
            XCTAssertTrue(hit.waitToAppear(), "The folder should be among the search results")
            hit.doubleClick()

            XCTAssertTrue(backButton(in: app).waitToAppear(), "Opening the result should push the folder")
            XCTAssertTrue(
                text(Fixture.file, in: app).waitToAppear(),
                "The opened folder should load its files, not stay on the skeleton"
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
