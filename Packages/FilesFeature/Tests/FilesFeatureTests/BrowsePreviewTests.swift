import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct BrowsePreviewTests {
    // MARK: Routing a row tap

    @Test("Tapping a folder asks the screen above to open it")
    func rowTappedOnDirectoryEmitsOpenFolderDelegate() async {
        let item = BrowseFixtures.folder(TestFolder.docs)
        let store = BrowseFixtures.store()

        await store.send(.rowTapped(item))
        await store.receive(.delegate(.openFolder(item)))
    }

    struct ViewerCase: Sendable, CustomTestStringConvertible {
        let name: String
        let reason: String

        var testDescription: String { "\(name) (\(reason))" }
    }

    @Test(
        "A file that needs no fetch only presents its viewer, and nothing is requested",
        arguments: [
            ViewerCase(name: "installer.exe", reason: "a known binary format"),
            ViewerCase(name: "clip.webm", reason: "streamable but not natively playable"),
            ViewerCase(name: "bundle.7z", reason: "an archive the app cannot list"),
            ViewerCase(name: "clip.mp4", reason: "streamable media plays live"),
            ViewerCase(name: FilesFeatureTestValue.bundleName, reason: "a browsable archive lists itself"),
        ]
    )
    func rowTappedOnAFileThatNeedsNoFetchSetsOnlyThePreviewItem(_ viewer: ViewerCase) async {
        let file = BrowseFixtures.file(viewer.name, size: 10)
        // No filesClient override: any preview, download or text fetch fails the test as unimplemented.
        let store = BrowseFixtures.store()

        await store.send(.rowTapped(file)) {
            $0.previewItem = file
        }
    }

    @Test("A text file shows its viewer at once and fetches the text, without any delegate")
    func rowTappedOnATextFileFetchesItsContentAndEmitsNoDelegate() async {
        let file = BrowseFixtures.file(TestFile.notes, size: 10)
        let store = BrowseFixtures.store {
            $0.filesClient.fetchTextContent = { _, _ in "hello world" }
        }

        await store.send(.rowTapped(file)) {
            $0.previewItem = file
            $0.textPhase = .loading
        }
        await store.receive(\.textContentResponse.success) {
            $0.textPhase = .loaded
            $0.textContent = "hello world"
        }
    }

    @Test("A text file that fails to fetch shows a readable message")
    func rowTappedOnATextFileFailingToFetchSurfacesAReadableErrorMessage() async {
        let file = BrowseFixtures.file(TestFile.notes, size: 10)
        let store = BrowseFixtures.store {
            $0.filesClient.fetchTextContent = { _, _ in throw FilesClientError.server(statusCode: 500) }
        }

        await store.send(.rowTapped(file)) {
            $0.previewItem = file
            $0.textPhase = .loading
        }
        await store.receive(\.textContentResponse.failure) {
            $0.textPhase = .failed(FilesClientError.server(statusCode: 500).userMessage)
        }
    }

    struct DownloadCase: Sendable, CustomTestStringConvertible {
        let name: String
        let endpoint: String
        let fileURL: URL

        var testDescription: String { "\(name) via \(endpoint)" }
    }

    @Test(
        "A previewable document or an SVG downloads through the preview endpoint, a Word document through the unrestricted download",
        arguments: [
            DownloadCase(name: TestFile.report, endpoint: "previewFile", fileURL: URL(fileURLWithPath: "/tmp/report.pdf")),
            DownloadCase(name: "logo.svg", endpoint: "previewFile", fileURL: URL(fileURLWithPath: "/tmp/logo.svg")),
            DownloadCase(name: "report.docx", endpoint: "downloadRawFile", fileURL: URL(fileURLWithPath: "/tmp/report.docx")),
        ]
    )
    func rowTappedOnADownloadedPreviewFetchesThroughTheRightEndpoint(_ download: DownloadCase) async {
        let file = BrowseFixtures.file(download.name, size: 10)
        let calls = LockIsolated<[String]>([])
        let store = BrowseFixtures.store {
            $0.filesClient.previewFile = { _, item in
                calls.withValue { $0.append("previewFile \(item.name)") }
                return download.fileURL
            }
            $0.filesClient.downloadRawFile = { _, item in
                calls.withValue { $0.append("downloadRawFile \(item.name)") }
                return download.fileURL
            }
        }

        await store.send(.rowTapped(file)) {
            $0.previewItem = file
            $0.previewPhase = .loading
        }
        await store.receive(\.previewFileResponse.success) {
            $0.previewPhase = .loaded
            $0.previewFileURL = download.fileURL
        }
        #expect(calls.value == ["\(download.endpoint) \(download.name)"])
    }

    @Test("A failed preview download shows a readable message")
    func aFailedPreviewDownloadSurfacesAReadableErrorMessage() async {
        let file = BrowseFixtures.file(TestFile.report, size: 10)
        let store = BrowseFixtures.store {
            $0.filesClient.previewFile = { _, _ in throw FilesClientError.server(statusCode: 415) }
        }

        await store.send(.rowTapped(file)) {
            $0.previewItem = file
            $0.previewPhase = .loading
        }
        await store.receive(\.previewFileResponse.failure) {
            $0.previewPhase = .failed(FilesClientError.server(statusCode: 415).userMessage)
        }
    }

    @Test("Dismissing the preview clears every part of its state")
    func previewDismissedClearsAllPreviewState() async {
        var state = BrowseFixtures.state()
        state.previewItem = BrowseFixtures.file(TestFile.notes, size: 10)
        state.previewFileURL = URL(fileURLWithPath: "/tmp/notes.txt")
        state.previewPhase = .failed("some error")
        let store = BrowseFixtures.store(state)

        await store.send(.previewDismissed) {
            $0.previewItem = nil
            $0.previewFileURL = nil
            $0.previewPhase = .idle
        }
    }

    // MARK: Google Drive stubs and the browser

    @Test("A Google Drive stub opens its link instead of showing a preview")
    func rowTappedOnAGoogleDriveStubOpensItsLinkInsteadOfPreviewing() async {
        let stub = BrowseFixtures.file("Budget.gsheet", size: 120)
        let opened = LockIsolated<[URL]>([])
        let store = BrowseFixtures.store {
            $0.filesClient.fetchTextContent = { _, _ in
                try FilesFeatureFixture.googleDriveStub.string()
            }
            $0.openURL = .init { url in
                opened.withValue { $0.append(url) }
                return true
            }
        }

        await store.send(.rowTapped(stub))
        await store.receive(\.googleDocsPointerResponse)
        await store.finish()

        #expect(opened.value.map(\.absoluteString) == ["https://docs.google.com/spreadsheets/d/ABC/edit"])
    }

    @Test("A Google Drive stub with no readable link falls back to the text viewer and opens nothing")
    func rowTappedOnAnUnreadableGoogleDriveStubFallsBackToTheTextViewer() async {
        let stub = BrowseFixtures.file("broken.gdoc", size: 5)
        let store = BrowseFixtures.store {
            $0.filesClient.fetchTextContent = { _, _ in "not json" }
            $0.openURL = .init { url in
                Issue.record("Opened \(url) for a stub without a link")
                return false
            }
        }

        await store.send(.rowTapped(stub))
        await store.receive(\.googleDocsPointerResponse) {
            $0.previewItem = stub
            $0.textPhase = .loading
        }
        await store.receive(\.textContentResponse.success) {
            $0.textPhase = .loaded
            $0.textContent = "not json"
        }
    }

    @Test("Open in Safari hands the raw file URL of an HTML page to the system")
    func openInBrowserHandsTheRawFileURLToSafari() async {
        let page = BrowseFixtures.file("index.html", in: "site", size: 40)
        let opened = LockIsolated<[URL]>([])
        let store = BrowseFixtures.store(BrowseFixtures.state("site")) {
            $0.openURL = .init { url in
                opened.withValue { $0.append(url) }
                return true
            }
        }

        await store.send(.openInBrowserTapped(page))
        await store.finish()

        #expect(opened.value == [URL(string: "https://example.com/api/raw?path=site/index.html")])
    }

    @Test("Open in Safari ignores a file that is not HTML")
    func openInBrowserIsIgnoredForNonHTMLFiles() async {
        let store = BrowseFixtures.store {
            $0.openURL = .init { url in
                Issue.record("Opened \(url) for a text file")
                return false
            }
        }

        await store.send(.openInBrowserTapped(BrowseFixtures.file(TestFile.notes, size: 4)))
    }

    // MARK: Saving text

    @Test("Saving text sends it to the server and shows it as the new content")
    func textSaveTappedSavesContentAndUpdatesState() async {
        var state = BrowseFixtures.state()
        state.previewItem = BrowseFixtures.file(TestFile.notes, size: 10)
        state.textContent = "hello"
        let saved = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(state) {
            $0.filesClient.saveTextContent = { _, path, content in saved.withValue { $0.append("\(path): \(content)") } }
        }

        await store.send(.textSaveTapped("hello world")) {
            $0.savingTexts = [TestFile.notes: "hello world"]
        }
        await store.receive(\.textSaveResponse) {
            $0.savingTexts = [:]
            $0.textContent = "hello world"
        }
        #expect(saved.value == ["notes.txt: hello world"])
    }

    @Test("A failed save shows a readable message and keeps the old content")
    func textSaveTappedFailureSurfacesAReadableErrorMessage() async {
        var state = BrowseFixtures.state()
        state.previewItem = BrowseFixtures.file(TestFile.notes, size: 10)
        state.textContent = "hello"
        let store = BrowseFixtures.store(state) {
            $0.filesClient.saveTextContent = { _, _, _ in throw FilesClientError.server(statusCode: 500) }
        }

        await store.send(.textSaveTapped("hello world")) {
            $0.savingTexts = [TestFile.notes: "hello world"]
        }
        await store.receive(\.textSaveResponse) {
            $0.savingTexts = [:]
            $0.textSaveError = FilesClientError.server(statusCode: 500).userMessage
        }
    }

    @Test("Saving with no file open does nothing")
    func textSaveTappedWithNoPreviewItemDoesNothing() async {
        let store = BrowseFixtures.store()

        await store.send(.textSaveTapped("orphaned content"))
    }

    // MARK: Actions that close the preview first

    struct Handoff: Sendable, CustomTestStringConvertible {
        let action: BrowseFeature.Action
        let delegate: BrowseFeature.Action.Delegate

        var testDescription: String { "\(delegate)" }
    }

    @Test(
        "An action taken from the preview closes the cover first, then reaches the tab after the settle delay",
        arguments: [
            Handoff(action: .openDownloadsFromPreview, delegate: .openDownloadsTapped),
            Handoff(action: .goToSharedTabFromPreview, delegate: .goToSharedTab),
        ]
    )
    func anActionFromThePreviewDismissesTheCoverThenSwitchesTabsAfterASettle(_ handoff: Handoff) async {
        var state = BrowseFixtures.state()
        state.previewItem = BrowseFixtures.file("archive.bin")
        let clock = TestClock()
        let store = BrowseFixtures.store(state) { $0.continuousClock = clock }

        await store.send(handoff.action)
        await store.receive(.previewDismissed) {
            $0.previewItem = nil
        }
        await clock.advance(by: .milliseconds(350))
        await store.receive(.delegate(handoff.delegate))
    }
}
