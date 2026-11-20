#if os(macOS)
    import CoreModels
    import Localization
    import XCTest

    /// File actions on the Mac: menus, context menus, rename, delete, Quick Look and previews.
    final class MacFileActionsUITests: MacUITestCase {
        /// In Documents: the File menu creates a folder; the file's right click menu starts with Open and
        /// renames in place; Return renames again, where ⌘A selects the name rather than every file;
        /// and the Delete key asks before deleting.
        func testCreateRenameAndDeleteInAFolder() {
            let app = launchApp()
            openDocuments(in: app)

            app.menuBars.menuBarItems[Constants.fileMenu].click()
            app.menuItems[L10n.Browse.actionNewFolder].click()
            let nameField = app.textFields[L10n.Browse.newFolderPlaceholder]
            XCTAssertTrue(nameField.waitToAppear(), "Create Folder should present the name sheet")
            nameField.clearAndType(Constants.newFolderName)
            app.labeledButton(L10n.Browse.newFolderConfirm).click()
            XCTAssertTrue(nameField.waitToVanish(), "A successful create should dismiss the sheet")
            XCTAssertTrue(
                text(Constants.newFolderName, in: app).waitToAppear(),
                "The new folder should appear in the table"
            )

            text(Fixture.file, in: app).rightClick()
            XCTAssertTrue(app.menuItems[L10n.Browse.open].waitToAppear(), "The file menu should offer Open")
            XCTAssertTrue(app.menuItems[L10n.Browse.actionRename].exists, "Right click should offer Rename")
            app.menuItems[L10n.Browse.actionRename].click()
            // The name cell turns into a text field in place, Finder style, with no sheet.
            let field = app.outlines.textFields.firstMatch
            XCTAssertTrue(field.waitToAppear(), "Rename should edit the name in the table")
            field.clearAndType(Constants.renamedFile)
            app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
            XCTAssertTrue(field.waitToVanish(), "Return should finish the rename")
            XCTAssertTrue(
                text(Constants.renamedFile, in: app).waitToAppear(),
                "The renamed file should appear in the table"
            )

            text(Constants.renamedFile, in: app).click()
            app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
            XCTAssertTrue(field.waitToAppear(), "Return should rename the selected file in place")
            XCTAssertTrue(field.isFocused(within: UITestTimeout.short))
            app.typeKey("a", modifierFlags: .command)
            field.typeText(Fixture.file)
            app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
            XCTAssertTrue(field.waitToVanish(), "Return in the field should finish the rename")
            XCTAssertTrue(
                text(Fixture.file, in: app).waitToAppear(),
                "⌘A then typing should replace the whole name"
            )

            text(Fixture.file, in: app).click()
            app.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
            let confirm = app.labeledButton(L10n.Trash.moveToTrash)
            XCTAssertTrue(confirm.waitToAppear(), "Delete should ask for confirmation first")
            confirm.click()
            XCTAssertTrue(text(Fixture.file, in: app).waitToVanish(), "The confirmed file should leave the table")
        }

        /// Space on a file toggles the system Quick Look panel, as in Finder, and several selected
        /// rows offer Move and Download, which the Mac has no select mode for.
        func testQuickLookTogglesAndSeveralRowsOfferMoveAndDownload() {
            let app = launchApp()
            let file = text(Fixture.file, in: app)
            let image = text(Fixture.imageFile, in: app)
            XCTAssertTrue(file.waitToAppear())
            file.waitToBeHittable()
            file.click()
            let windowsBefore = app.windows.count
            app.typeKey(XCUIKeyboardKey.space, modifierFlags: [])
            XCTAssertTrue(
                waitUntil(NSPredicate(format: "count > %d", windowsBefore), on: app.windows),
                "Space should open Quick Look"
            )
            app.typeKey(XCUIKeyboardKey.space, modifierFlags: [])
            XCTAssertTrue(
                waitUntil(NSPredicate(format: "count == %d", windowsBefore), on: app.windows),
                "Space again should close Quick Look"
            )

            XCUIElement.perform(withKeyModifiers: .command) { image.click() }
            image.rightClick()
            XCTAssertTrue(
                app.menuItems[L10n.Browse.actionDownload].waitToAppear(),
                "Several rows should offer Download"
            )
            XCTAssertTrue(app.menuItems[L10n.Browse.actionMove].exists, "Several rows should offer Move")
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        }

        /// A text preview is a sheet with its own Close and Edit, and Esc closes it; closing it with
        /// unsaved edits asks to save, and Don't Save closes without saving.
        func testTextPreviewClosesAndAsksToSaveEdits() {
            let app = launchApp()
            let file = text(Fixture.file, in: app)
            XCTAssertTrue(file.waitToAppear())
            file.waitToBeHittable()
            file.doubleClick()
            let sheet = app.sheets.firstMatch
            XCTAssertTrue(sheet.waitToAppear(), "Double click should open the preview")
            XCTAssertTrue(
                sheet.buttons.labeled(L10n.PreviewToolbar.close).waitToAppear(),
                "The preview needs a Close button"
            )
            XCTAssertTrue(sheet.buttons.labeled(L10n.Common.edit).waitToAppear(), "A text preview needs Edit")
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            XCTAssertTrue(sheet.waitToVanish(), "Esc should close the preview")

            file.doubleClick()
            XCTAssertTrue(sheet.waitToAppear())
            let edit = sheet.buttons.labeled(L10n.Common.edit)
            XCTAssertTrue(edit.waitToAppear())
            edit.click()
            let editor = sheet.textViews.firstMatch
            XCTAssertTrue(editor.waitToAppear(), "Edit should make the text editable")
            editor.click()
            editor.typeText("changed")
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            let dontSave = app.windows.buttons.titled(L10n.TextPreview.dontSave)
            XCTAssertTrue(dontSave.waitToAppear(), "Closing with unsaved edits should ask to save")
            dontSave.click()
            XCTAssertTrue(sheet.waitToVanish(), "Don't Save should close the preview")
        }
    }
#endif
