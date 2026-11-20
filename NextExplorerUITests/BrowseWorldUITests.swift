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

        /// An empty folder says so, and folders four deep open and Back walks up the chain.
        func testAnEmptyFolderAndFoldersFourDeepWalkBackUp() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            open(.projects, in: browse)
            open(.drafts, in: browse)
            XCTAssertTrue(browse.emptyStateMessage.waitToAppear(), "A folder with nothing in it says so")
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(browse.folderNavigationBar(Folder.projects.name).waitToAppear())

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

        /// A file opens its preview and goes back, a folder opens to its own contents, and a file
        /// nothing can open there says so.
        func testFilesAndFoldersOpenAndAFileNothingCanOpenSaysSo() {
            let app = launchApp(auth: .loggedIn, scenario: .normal)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(Fixture.file).waitToAppear())
            // The first tap after launch is occasionally dropped, so retry once (see `openMenu`).
            openMenu({ browse.item(Fixture.file).tap() }, until: browse.previewBackButton)
            browse.previewBackButton.tap()

            open(.documents, in: browse)
            // A folder only Documents holds proves the navigation resolved rather than dead ended.
            XCTAssertTrue(
                browse.item(Folder.invoices.name).waitToAppear(),
                "Navigating into a folder should load its contents"
            )
            XCTAssertTrue(scrollTo(browse.item(File.export.name), in: app))

            openMenu(
                { browse.item(File.export.name).tap() },
                until: app.staticTexts[L10n.UnsupportedPreview.cannotOpen]
            )
        }
    }
#endif
