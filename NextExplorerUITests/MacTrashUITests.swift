#if os(macOS)
    import CoreModels
    import Localization
    import XCTest

    /// The Mac trash: a deleted file shows in the Trash section and comes back from it.
    final class MacTrashUITests: MacUITestCase {
        func testADeletedFileIsRestoredFromTheTrashSection() {
            let app = launchApp()
            openDocuments(in: app)

            text(Fixture.file, in: app).click()
            app.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
            let confirm = app.labeledButton(L10n.Common.delete)
            XCTAssertTrue(confirm.waitToAppear(), "Delete should ask for confirmation first")
            confirm.click()
            XCTAssertTrue(text(Fixture.file, in: app).waitToVanish(), "The confirmed file should leave the table")

            sidebarItem(L10n.Trash.title, in: app).click()
            let trashed = text(Fixture.file, in: app)
            XCTAssertTrue(trashed.waitToAppear(), "The deleted file should be in the Trash section")

            trashed.rightClick()
            XCTAssertTrue(app.menuItems[L10n.Trash.restore].waitToAppear(), "Right click should offer Restore")
            app.menuItems[L10n.Trash.restore].click()
            XCTAssertTrue(trashed.waitToVanish(), "The restored file should leave the trash")
        }
    }
#endif
