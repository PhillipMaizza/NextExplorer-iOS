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
    }
#endif
