#if os(macOS)
    import CoreModels
    import Localization
    import XCTest

    /// Undo and redo of file operations on the Mac: the Edit menu and the toast a move shows.
    final class MacUndoRedoUITests: MacUITestCase {
        private enum Constants {
            static let editMenu = "Edit"
            static let newFolderName = "Reports"
        }

        private func edit(_ title: String, in app: XCUIApplication) {
            app.menuBars.menuBarItems[Constants.editMenu].click()
            let item = app.menuItems[title]
            XCTAssertTrue(item.waitToAppear(), "The Edit menu should offer \(title)")
            item.click()
        }

        func testTheMoveToastUndoesTheMoveAndGoesAway() {
            let app = launchApp()
            openDocuments(in: app)

            // A folder made here starts empty, so the move meets no name conflict.
            app.menuBars.menuBarItems[MacUITestCase.Constants.fileMenu].click()
            app.menuItems[L10n.Browse.actionNewFolder].click()
            let field = app.textFields[L10n.Browse.newFolderPlaceholder]
            XCTAssertTrue(field.waitToAppear())
            field.clearAndType(Constants.newFolderName)
            app.labeledButton(L10n.Browse.newFolderConfirm).click()
            let target = text(Constants.newFolderName, in: app)
            XCTAssertTrue(target.waitToAppear())

            // Move… rather than a drag: a drag only starts after a timed press.
            let file = text(Fixture.file, in: app)
            let move = app.menuItems[L10n.Browse.actionMove]
            openMenu({ file.rightClick() }, until: move)
            move.click()
            let sheet = app.sheets.firstMatch
            XCTAssertTrue(sheet.waitToAppear(), "Move should open the folder picker")
            openInPicker(Fixture.folder, in: sheet, app: app)
            openInPicker(Constants.newFolderName, in: sheet, app: app)
            // Only a folder the file can go to enables Move Here: the root and its own folder do not.
            let moveHere = sheet.buttons.labeled(L10n.Browse.destinationPickerConfirmMove)
            XCTAssertTrue(moveHere.isEnabled(within: UITestTimeout.standard), "The new folder should take the file")
            moveHere.click()
            XCTAssertTrue(file.waitToVanish(), "Moving the file into the folder should take it out of this one")

            let undo = app.buttons[L10n.Menu.undo].firstMatch
            XCTAssertTrue(undo.waitToAppear(), "The move toast should offer Undo")
            undo.click()

            XCTAssertTrue(undo.waitToVanish(), "Tapping Undo should dismiss the toast")
            XCTAssertTrue(file.waitToAppear(), "Undo should bring the file back")

            target.click()
            edit(L10n.Menu.redo, in: app)
            XCTAssertTrue(file.waitToVanish(), "Redo should move the file again")

            target.doubleClick()
            XCTAssertTrue(file.waitToAppear(), "The file should be in the folder it was moved to")
        }

        /// Selects a folder in the Move picker and opens it with ⌘↓.
        private func openInPicker(_ name: String, in sheet: XCUIElement, app: XCUIApplication) {
            let row = sheet.staticTexts.showing(name)
            XCTAssertTrue(row.waitToAppear(), "The picker should list \(name)")
            row.click()
            app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: .command)
        }
    }
#endif
