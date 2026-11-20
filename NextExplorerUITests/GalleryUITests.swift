#if os(iOS)
    import CoreModels
    import Localization
    import XCTest

    /// The gallery pages through every file in a folder: each kind shows as its
    /// own page, text hands over to the editor and back, and deleting keeps the gallery open on the
    /// neighbour. Data comes from the mocked `gallery` scenario.
    final class GalleryUITests: UITestCase {
        /// The `gallery` scenario's files in list order (mirrors `UITestSupport.galleryItems`).
        private enum Fixture {
            static let archive = "archive.zip"
            static let video = "clip.mp4"
            static let unsupported = "installer.dmg"
            static let text = "notes.txt"
            static let document = "report.pdf"
            static let sunset = "sunset.jpg"
            static let image = "vacation.jpg"
            /// The one subfolder: the gallery skips it, a move can land there.
            static let folder = "Projects"
            /// The first line of what a text file reads back (mirrors `UITestSupport.galleryNotesText`).
            static let notesText = "Gallery notes"
            static let renamedDocument = "summary.pdf"
            static let everyFile = [archive, video, unsupported, text, document, image]
            static let saveTitles = [
                L10n.PreviewToolbar.savePhoto,
                L10n.PreviewToolbar.saveVideo,
                L10n.PreviewToolbar.saveToDevice,
            ]
        }

        /// One walk through the folder: each kind shows as its own page, a text page shows its text,
        /// and a swipe the other way goes back.
        func testSwipesThroughEveryKindOfFile() {
            let app = openGallery(at: Fixture.archive)
            keepScreenshot(of: Fixture.archive, in: app)
            XCTAssertTrue(app.labeledButton(L10n.Browse.open).waitToAppear(), "A zip page offers Open")

            swipeToPage(Fixture.video, in: app)
            XCTAssertTrue(app.labeledButton(L10n.Media.play).waitToAppear(), "A video swiped to waits for Play")

            swipeToPage(Fixture.unsupported, in: app)
            XCTAssertTrue(
                app.staticTexts[L10n.UnsupportedPreview.cannotOpen].waitToAppear(),
                "A file with no viewer says so on its page"
            )

            swipeToPage(Fixture.text, in: app)
            XCTAssertTrue(app.labeledButton(L10n.Common.edit).waitToAppear(), "A text page offers Edit")
            XCTAssertTrue(
                app.descendants(matching: .any)
                    .matching(NSPredicate(
                        format: "value CONTAINS %@ OR label CONTAINS %@",
                        Fixture.notesText,
                        Fixture.notesText
                    ))
                    .firstMatch.waitToAppear(),
                "A text page shows the file's text"
            )

            swipeToPage(Fixture.document, in: app)
            XCTAssertFalse(
                app.labeledButton(L10n.Common.edit).exists,
                "Only a text page offers Edit"
            )

            swipeToPage(Fixture.sunset, in: app)
            swipeToPage(Fixture.image, in: app)
            swipeToPage(Fixture.sunset, in: app, backwards: true)
        }

        func testEditOpensTheEditorAndCloseReturnsToTheList() {
            let app = openGallery(at: Fixture.text)
            app.labeledButton(L10n.Common.edit).tap()
            XCTAssertTrue(
                app.labeledButton(L10n.Common.save).waitToAppear(),
                "Edit opens the editor ready to type"
            )

            app.labeledButton(L10n.Common.close).tap()
            XCTAssertTrue(
                app.labeledButton(L10n.Common.edit).waitToAppear(),
                "Closing the editor goes back to the gallery"
            )
            XCTAssertTrue(title(Fixture.text, in: app).exists, "The gallery stays on the edited file")

            let browse = BrowseScreen(app: app)
            browse.previewBackButton.tap()
            XCTAssertTrue(browse.item(Fixture.document).waitToAppear(), "Close goes back to the folder")
        }

        func testOpenedVideoPlayerFillsItsPage() {
            let app = openGallery(at: Fixture.video)
            let player = app.otherElements[AccessibilityIdentifiers.Media.player].firstMatch
            XCTAssertTrue(player.waitToAppear(), "The opened video has a player on its page")
            XCTAssertEqual(
                player.frame.width,
                app.windows.firstMatch.frame.width,
                accuracy: 1,
                "A playing page keeps the width of the screen, so the next page stays off screen"
            )
        }

        func testTapHidesAndShowsTheBarsOnEveryKindOfPage() {
            let app = openGallery(at: Fixture.document)
            toggleBars(on: Fixture.document, in: app)
            swipeToPage(Fixture.text, in: app, backwards: true)
            toggleBars(on: Fixture.text, in: app)
            swipeToPage(Fixture.document, in: app)
            swipeToPage(Fixture.sunset, in: app)
            swipeToPage(Fixture.image, in: app)
            toggleBars(on: Fixture.image, in: app)
        }

        /// Every kind's title menu in one walk: the same actions everywhere, and only its own save.
        func testEveryKindOfFileOffersEveryActionWithItsOwnSave() {
            let app = openGallery(at: Fixture.everyFile[0])
            for (index, name) in Fixture.everyFile.enumerated() {
                if index > 0 {
                    swipeToPage(name, in: app)
                }
                let save = saveTitle(for: name)
                openMenu({ title(name, in: app).tap() }, until: app.labeledButton(save))
                for label in [
                    L10n.Browse.actionGetInfo,
                    L10n.PreviewToolbar.rename,
                    L10n.Browse.actionMove,
                    L10n.Browse.actionCopy,
                    L10n.PreviewToolbar.createShareLink,
                    L10n.PreviewToolbar.share,
                    L10n.Browse.actionAvailableOffline,
                    L10n.PreviewToolbar.delete,
                ] {
                    XCTAssertTrue(app.labeledButton(label).exists, "\(name)'s title menu offers \(label)")
                }
                for other in Fixture.saveTitles where other != save {
                    XCTAssertFalse(app.labeledButton(other).exists, "\(name) only offers \(save), not \(other)")
                }
                keepScreenshot(of: "\(name) title menu", in: app)
                dismissMenu(showing: save, in: app)
            }
        }

        func testEverySaveConfirmsOverTheGallery() {
            let app = openGallery(at: Fixture.video)
            save(Fixture.video, in: app)
            for name in [Fixture.unsupported, Fixture.text, Fixture.document] {
                swipeToPage(name, in: app)
            }
            save(Fixture.document, in: app)
            swipeToPage(Fixture.sunset, in: app)
            swipeToPage(Fixture.image, in: app)
            save(Fixture.image, in: app)
        }

        /// Get Info, Copy and Create Share Link each come up over the gallery, which stays put.
        func testSheetsAndConfirmationsOpenOverTheGallery() {
            let app = openGallery(at: Fixture.document)
            choose(L10n.Browse.actionGetInfo, from: Fixture.document, in: app)
            XCTAssertTrue(
                app.staticTexts[L10n.FileInfo.rowDateModified].waitToAppear(),
                "Get Info shows the file's details over the gallery"
            )
            keepScreenshot(of: "get info", in: app)
            app.buttons.matching(NSPredicate(format: "label == %@", L10n.Common.close))
                .allElementsBoundByIndex.last { $0.isHittable }?.tap()
            XCTAssertTrue(title(Fixture.document, in: app).waitToAppear(), "Closing the sheet leaves the gallery open")

            choose(L10n.Browse.actionCopy, from: Fixture.document, in: app)
            XCTAssertTrue(
                app.staticTexts[L10n.Browse.clipboardCopiedOne(Fixture.document)].waitToAppear(),
                "Copy says the file is ready to paste, over the gallery"
            )
            XCTAssertTrue(title(Fixture.document, in: app).exists, "Copy keeps the gallery on the same file")

            choose(L10n.PreviewToolbar.createShareLink, from: Fixture.document, in: app)
            XCTAssertTrue(
                BrowseScreen(app: app).createShareSubmit.waitToAppear(),
                "Create Share Link opens the link sheet over the gallery"
            )
            keepScreenshot(of: "share link", in: app)
        }

        func testShareOpensTheSystemShareSheet() {
            let app = openGallery(at: Fixture.document)
            choose(L10n.PreviewToolbar.share, from: Fixture.document, in: app)
            XCTAssertTrue(
                app.descendants(matching: .any)[AccessibilityIdentifiers.Share.sheet].waitToAppear(),
                "Share downloads the file and opens the system share sheet"
            )
            keepScreenshot(of: "system share", in: app)
        }

        /// Move, rename and delete in a row: the gallery stays open each time, on the neighbour when
        /// the file leaves the folder and on the new name when it is renamed.
        func testMoveRenameAndDeleteKeepTheGalleryOpen() {
            let app = openGallery(at: Fixture.text)
            let browse = BrowseScreen(app: app)

            choose(L10n.Browse.actionMove, from: Fixture.text, in: app)
            XCTAssertTrue(
                app.staticTexts[L10n.Browse.destinationPickerMoveTitle].waitToAppear(),
                "Move opens the folder picker over the gallery"
            )
            let folderRow = app.staticTexts.matching(NSPredicate(format: "label == %@", Fixture.folder))
                .allElementsBoundByIndex.last { $0.isHittable }
            XCTAssertNotNil(folderRow, "The picker lists the subfolder")
            folderRow?.tap()
            app.labeledButton(L10n.Browse.destinationPickerConfirmMove).tap()
            XCTAssertTrue(
                title(Fixture.document, in: app).waitToAppear(),
                "The moved file leaves and the next one takes its place"
            )
            XCTAssertTrue(browse.previewBackButton.exists, "The gallery stays open")

            choose(L10n.PreviewToolbar.rename, from: Fixture.document, in: app)
            XCTAssertTrue(browse.renameNameField.waitToAppear(), "Rename opens the rename sheet over the gallery")
            browse.renameNameField.clearAndType(Fixture.renamedDocument)
            browse.renameConfirm.tap()
            XCTAssertTrue(browse.renameNameField.waitToVanish(), "A successful rename dismisses the sheet")
            XCTAssertTrue(
                title(Fixture.renamedDocument, in: app).waitToAppear(),
                "The gallery title shows the new name"
            )

            // Delete sits in the title menu, so the page's bottom stays free for its content.
            choose(L10n.PreviewToolbar.delete, from: Fixture.renamedDocument, in: app)
            let confirm = app.buttons[L10n.Trash.moveToTrash].firstMatch
            XCTAssertTrue(confirm.waitToAppear(), "Delete asks first")
            keepScreenshot(of: "delete confirmation", in: app)
            confirm.tap()
            XCTAssertTrue(
                title(Fixture.sunset, in: app).waitToAppear(),
                "The next file takes the deleted one's place"
            )
            XCTAssertTrue(browse.previewBackButton.exists, "The gallery stays open")
        }

        func testOfflineToggleTurnsIntoARemoval() {
            let app = openGallery(at: Fixture.document)
            let browse = BrowseScreen(app: app)
            choose(L10n.Browse.actionAvailableOffline, from: Fixture.document, in: app)

            // The mocked download finishes at once, so the menu offers the removal next time.
            openMenu({ title(Fixture.document, in: app).tap() }, until: browse.removeFromOfflineAction)
            XCTAssertFalse(browse.availableOfflineAction.exists, "A pinned file no longer offers Available Offline")
            keepScreenshot(of: "offline on", in: app)
            browse.removeFromOfflineAction.tap()
            XCTAssertTrue(browse.removeOfflineConfirmButton.waitToAppear(), "Removing asks first")
            browse.removeOfflineConfirmButton.tap()

            openMenu({ title(Fixture.document, in: app).tap() }, until: browse.availableOfflineAction)
            XCTAssertFalse(browse.removeFromOfflineAction.exists, "A removed file offers Available Offline again")
        }

        // MARK: Helpers

        /// Opens the title menu of the file on screen and taps `action`.
        private func choose(_ action: String, from name: String, in app: XCUIApplication) {
            let item = app.labeledButton(action)
            openMenu({ title(name, in: app).tap() }, until: item)
            item.tap()
        }

        /// Saves the file on screen and checks the save confirms over the gallery, which stays on it.
        private func save(_ name: String, in app: XCUIApplication) {
            choose(saveTitle(for: name), from: name, in: app)
            XCTAssertTrue(
                app.staticTexts[L10n.DownloadQueue.barTitleOne(name)].waitToAppear(),
                "\(saveTitle(for: name)) confirms over the gallery"
            )
            XCTAssertTrue(title(name, in: app).exists, "Saving keeps the gallery on \(name)")
        }

        /// A tap hides the page's bars and another brings them back.
        private func toggleBars(on name: String, in app: XCUIApplication) {
            let close = BrowseScreen(app: app).previewBackButton
            XCTAssertTrue(close.waitToAppear(), "\(name) shows its bars")
            app.tap()
            XCTAssertTrue(close.waitToVanish(), "A tap on \(name) hides the bars")
            keepScreenshot(of: "\(name) bars hidden", in: app)
            app.tap()
            XCTAssertTrue(close.waitToAppear(), "Another tap on \(name) brings the bars back")
        }

        /// Closes the open title menu with a tap below it. The tap can also reach the page and hide
        /// its bars, so they come back before the walk goes on.
        private func dismissMenu(showing item: String, in app: XCUIApplication) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
            XCTAssertTrue(app.labeledButton(item).waitToVanish(), "The title menu closes")
            if !BrowseScreen(app: app).previewBackButton.appears(within: UITestTimeout.short) {
                app.tap()
            }
        }

        /// A photo saves to Photos, a video to Photos as a video, anything else to the device.
        private func saveTitle(for name: String) -> String {
            switch name {
            case Fixture.image, Fixture.sunset: L10n.PreviewToolbar.savePhoto
            case Fixture.video: L10n.PreviewToolbar.saveVideo
            default: L10n.PreviewToolbar.saveToDevice
            }
        }

        /// Launches into the mixed folder and opens `name` from the list.
        private func openGallery(at name: String) -> XCUIApplication {
            let app = launchApp(auth: .loggedIn, scenario: .gallery)
            let browse = BrowseScreen(app: app)
            XCTAssertTrue(browse.item(name).waitToAppear())
            // The first tap after launch is occasionally dropped, so retry once (see `openMenu`).
            openMenu({ browse.item(name).tap() }, until: title(name, in: app))
            return app
        }

        /// The gallery's title, which names the file on screen (a button, since it opens a menu).
        private func title(_ name: String, in app: XCUIApplication) -> XCUIElement {
            app.navigationBars.descendants(matching: .any).labeled(name)
        }

        private func swipeToPage(
            _ name: String,
            in app: XCUIApplication,
            backwards: Bool = false,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            let swipe = { backwards ? app.swipeRight() : app.swipeLeft() }
            swipe()
            // A swipe landing while the cover still animates in is dropped, so retry once.
            if !title(name, in: app).appears(within: UITestTimeout.short) {
                swipe()
            }
            XCTAssertTrue(
                title(name, in: app).waitToAppear(
                    UITestTimeout.standard,
                    "Swiping shows \(name)",
                    file: file,
                    line: line
                )
            )
            keepScreenshot(of: name, in: app)
        }

        /// Keeps a picture of the page in the test results, to see what each kind of file looks like.
        private func keepScreenshot(of name: String, in app: XCUIApplication) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
#endif
