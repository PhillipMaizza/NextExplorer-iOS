import XCTest

/// Critical path: opening a text file, entering edit mode and saving. Runestone's text view is a
/// custom control, so this drives the Edit/Save toggle rather than typing into the buffer.
final class EditorUITests: UITestCase {
    func testEditAndSaveTextFile() {
        let app = launchApp(auth: .loggedIn, scenario: .normal)
        let browse = BrowseScreen(app: app)
        XCTAssertTrue(browse.item(Fixture.file).waitToAppear())

        let editor = TextPreviewScreen(app: app)
        // Opening the file is a navigation that XCUITest can occasionally drop under load; retry.
        openMenu({ browse.item(Fixture.file).tap() }, until: editor.editButton)
        editor.editButton.tap()

        XCTAssertTrue(editor.saveButton.waitToAppear(), "Entering edit mode should reveal Save")
        editor.saveButton.tap()

        XCTAssertTrue(editor.editButton.waitToAppear(), "Saving should return to the read only Edit control")
    }
}
