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

        func testUndoAndRedoANewFolderFromTheEditMenu() {
            let app = launchApp()
            openDocuments(in: app)

            app.menuBars.menuBarItems[MacUITestCase.Constants.fileMenu].click()
            app.menuItems[L10n.Browse.actionNewFolder].click()
            let field = app.textFields[L10n.Browse.newFolderPlaceholder]
            XCTAssertTrue(field.waitToAppear(), "New Folder should present the name sheet")
            field.clearAndType(Constants.newFolderName)
            app.labeledButton(L10n.Browse.newFolderConfirm).click()
            let folder = text(Constants.newFolderName, in: app)
            XCTAssertTrue(folder.waitToAppear(), "The new folder should appear in the table")

            // The menu reaches the file table only while it has focus.
            text(Fixture.file, in: app).click()
            edit(L10n.Menu.undo, in: app)
            XCTAssertTrue(folder.waitToVanish(UITestTimeout.slow), "Undo should delete the new folder")

            edit(L10n.Menu.redo, in: app)
            XCTAssertTrue(folder.waitToAppear(UITestTimeout.slow), "Redo should make the folder again")
        }

        func testTheMoveToastUndoesTheMove() {
            let app = launchApp()
            let file = moveFileIntoANewFolder(in: app)

            let undo = app.buttons[L10n.Menu.undo].firstMatch
            XCTAssertTrue(undo.waitToAppear(UITestTimeout.slow, "The move toast should offer Undo"))
            undo.click()

            XCTAssertTrue(undo.waitToVanish(UITestTimeout.slow), "Tapping Undo should dismiss the toast")
            XCTAssertTrue(file.waitToAppear(UITestTimeout.slow, "Undo should bring the file back"))
        }

        func testRedoFromTheEditMenuRepeatsAnUndoneMove() {
            let app = launchApp()
            let file = moveFileIntoANewFolder(in: app)

            edit(L10n.Menu.undo, in: app)
            XCTAssertTrue(file.waitToAppear(UITestTimeout.slow, "Undo should bring the file back"))

            edit(L10n.Menu.redo, in: app)
            XCTAssertTrue(file.waitToVanish(UITestTimeout.slow), "Redo should move the file again")
        }

        /// Makes an empty folder (so the move meets no name conflict) and moves the fixture file into it
        /// with Move, not a drag, because a drag only starts after a timed press.
        private func moveFileIntoANewFolder(in app: XCUIApplication) -> XCUIElement {
            openDocuments(in: app)
            app.menuBars.menuBarItems[MacUITestCase.Constants.fileMenu].click()
            app.menuItems[L10n.Browse.actionNewFolder].click()
            let field = app.textFields[L10n.Browse.newFolderPlaceholder]
            XCTAssertTrue(field.waitToAppear(UITestTimeout.slow, "New Folder should present the name sheet"))
            field.clearAndType(Constants.newFolderName)
            app.labeledButton(L10n.Browse.newFolderConfirm).click()
            XCTAssertTrue(
                text(Constants.newFolderName, in: app).waitToAppear(UITestTimeout.slow, "The new folder should appear")
            )

            let file = text(Fixture.file, in: app)
            let move = app.menuItems[L10n.Browse.actionMove]
            openMenu({ file.rightClick() }, until: move)
            move.click()
            let sheet = app.sheets.firstMatch
            XCTAssertTrue(sheet.waitToAppear(UITestTimeout.slow, "Move should open the folder picker"))
            openInPicker(Fixture.folder, in: sheet, app: app)
            openInPicker(Constants.newFolderName, in: sheet, app: app)
            // Only a folder the file can go to enables Move Here: the root and its own folder do not.
            let moveHere = sheet.buttons.labeled(L10n.Browse.destinationPickerConfirmMove)
            XCTAssertTrue(moveHere.isEnabled(within: UITestTimeout.slow), "The new folder should take the file")
            moveHere.click()
            XCTAssertTrue(file.waitToVanish(UITestTimeout.slow), "Moving the file should take it out of this folder")
            return file
        }

        /// Selects a folder in the Move picker and opens it with Command Down.
        private func openInPicker(_ name: String, in sheet: XCUIElement, app: XCUIApplication) {
            let row = sheet.staticTexts.showing(name)
            XCTAssertTrue(row.waitToAppear(UITestTimeout.slow, "The picker should list \(name)"))
            row.click()
            app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: .command)
        }
    }
#endif
