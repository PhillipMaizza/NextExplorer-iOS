#if os(macOS)
    import CoreModels
    import Localization
    import XCTest

    /// Undo and redo of file operations on the Mac: the Edit menu and the toast a move shows.
    final class MacUndoRedoUITests: MacUITestCase {
        private enum Constants {
            static let editMenu = "Edit"
            static let newFolderName = "Reports"
            static let dragHold: TimeInterval = 0.6
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
            XCTAssertTrue(folder.waitToVanish(), "Undo should delete the new folder")

            edit(L10n.Menu.redo, in: app)
            XCTAssertTrue(folder.waitToAppear(), "Redo should make the folder again")
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

            let file = text(Fixture.file, in: app)
            // A Mac table row starts dragging only after the button has been held a moment.
            file.click(forDuration: Constants.dragHold, thenDragTo: target)
            XCTAssertTrue(file.waitToVanish(), "Dropping the file on a folder should move it there")

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
    }
#endif
