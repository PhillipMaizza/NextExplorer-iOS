#if os(iOS)
    import CoreModels
    import Localization
    import XCTest

    /// The browse tree's own states: a read only folder, an empty one, a deep chain, a folder far
    /// longer than one screen and a file nothing on the device opens.
    final class BrowseWorldUITests: UITestCase {
        private typealias Folder = UITestFixture.Folder
        private typealias File = UITestFixture.File
        private typealias Series = UITestFixture.Series

        private func open(_ folder: Folder, in browse: BrowseScreen) {
            XCTAssertTrue(browse.item(folder.name).waitToAppear())
            openMenu({ browse.item(folder.name).tap() }, until: browse.folderNavigationBar(folder.name))
        }

        func testAReadOnlyFolderOffersNoRenameOrDelete() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            open(.teamLibrary, in: browse)

            openMenu({ browse.row(File.handbook.name).longPress() }, until: browse.saveToDeviceAction)
            XCTAssertFalse(browse.renameAction.exists, "Nothing in a read only folder can be renamed")
            XCTAssertFalse(browse.deleteAction.exists, "Nothing in a read only folder can be deleted")
        }

        func testAnEmptyFolderShowsTheEmptyState() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            open(.projects, in: browse)
            open(.drafts, in: browse)

            XCTAssertTrue(browse.emptyStateMessage.waitToAppear(), "A folder with nothing in it says so")
        }

        func testFoldersFourDeepOpenAndBackWalksUpTheChain() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            open(.projects, in: browse)
            for folder in Folder.nestedChain {
                open(folder, in: browse)
            }
            XCTAssertTrue(browse.item(File.agenda.name).waitToAppear(), "The deepest folder lists its file")

            for parent in ([Folder.projects] + Folder.nestedChain.dropLast()).reversed() {
                app.navigationBars.buttons.firstMatch.tap()
                XCTAssertTrue(browse.folderNavigationBar(parent.name).waitToAppear(), "Back lands on \(parent.name)")
            }
        }

        func testSearchingALongFolderFindsItsLastPhoto() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            open(.photos, in: browse)
            open(.cameraRoll, in: browse)
            XCTAssertTrue(browse.item(Series.cameraRollPhoto(1)).waitToAppear())
            XCTAssertFalse(browse.item(Series.lastCameraRollPhoto).isHittable, "The last photo starts off screen")

            XCTAssertTrue(browse.searchField.waitToAppear())
            browse.searchField.clearAndType(Series.lastCameraRollPhoto)
            XCTAssertTrue(
                browse.item(Series.lastCameraRollPhoto).waitToAppear(),
                "Search reaches past the first screen"
            )
        }

        func testAFileNothingCanOpenSaysSo() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            open(.documents, in: browse)
            XCTAssertTrue(scrollTo(browse.item(File.export.name), in: app))

            openMenu(
                { browse.item(File.export.name).tap() },
                until: app.staticTexts[L10n.UnsupportedPreview.cannotOpen]
            )
        }
    }
#endif
