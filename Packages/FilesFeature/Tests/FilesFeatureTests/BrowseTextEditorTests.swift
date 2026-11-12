import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// Saving text from the editor: a save outlives the preview that started it, a second file can be
/// saved beside a pending one, and a file changed on the server asks before it is overwritten.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseTextEditorTests {
    private let notes = BrowseFixtures.file(TestFile.notes, in: TestFolder.docs)
    private let other = BrowseFixtures.file("other.txt", in: TestFolder.docs)

    private func editingState() -> BrowseFeature.State {
        var state = BrowseFixtures.loadedState(TestFolder.docs, items: [notes, other])
        state.previewItem = notes
        state.textContent = TestValue.outdated
        state.textPhase = .loaded
        return state
    }

    private func conflictStore(
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<BrowseFeature> {
        BrowseFixtures.store(editingState()) {
            $0.filesClient.saveTextContent = { _, _, _ in throw FilesClientError.changedOnServer }
            configure(&$0)
        }
    }

    /// Saves `text` and lets the server answer that the file changed since the editor opened it.
    private func saveIntoAConflict(_ store: TestStoreOf<BrowseFeature>, text: String = "mine") async {
        await store.send(.textSaveTapped(text)) {
            $0.savingTexts[notes.id] = text
        }
        await store.receive(\.textSaveResponse) {
            $0.savingTexts = [:]
            $0.textSaveConflict = BrowseFeature.State.TextSaveConflict(pendingText: text)
            $0.textSaveError = FilesClientError.changedOnServer.userMessage
        }
    }

    // MARK: Save overlap

    @Test("A save finishing after the preview closed never writes the editor content")
    func aSaveFinishingAfterThePreviewClosedNeverWritesTheEditorContent() async {
        let gate = AsyncGate()
        let store = BrowseFixtures.store(editingState()) {
            $0.filesClient.saveTextContent = { _, _, _ in try await gate.wait() }
        }

        await store.send(.textSaveTapped("new")) {
            $0.savingTexts[notes.id] = "new"
        }
        #expect(store.state.isSavingTextContent)
        await store.send(.previewDismissed) {
            $0.previewItem = nil
            $0.textContent = nil
            $0.textPhase = .idle
        }
        gate.open()
        await store.receive(\.textSaveResponse) {
            $0.savingTexts = [:]
        }
    }

    @Test("A save failing after the preview closed is reported as a toast")
    func aSaveFailingAfterThePreviewClosedIsReportedAsAToast() async {
        let gate = AsyncGate()
        let store = BrowseFixtures.store(editingState()) {
            $0.filesClient.saveTextContent = { _, _, _ in
                try await gate.wait()
                throw FilesClientError.server(statusCode: 500)
            }
        }

        await store.send(.textSaveTapped("new")) {
            $0.savingTexts[notes.id] = "new"
        }
        await store.send(.previewDismissed) {
            $0.previewItem = nil
            $0.textContent = nil
            $0.textPhase = .idle
        }
        gate.open()
        await store.receive(\.textSaveResponse) {
            $0.savingTexts = [:]
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 500).userMessage
        }
    }

    @Test("A second save of the same file is ignored while the first is still in flight, even after the preview was reopened")
    func aSecondSaveIsIgnoredWhileTheFirstIsStillInFlight() async {
        let gate = AsyncGate()
        let saves = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(editingState()) {
            $0.filesClient.saveTextContent = { _, _, content in
                saves.withValue { $0.append(content) }
                try await gate.wait()
            }
            $0.filesClient.fetchTextContent = { _, _ in "on the server" }
        }

        await store.send(.textSaveTapped("one")) {
            $0.savingTexts[notes.id] = "one"
        }
        await store.send(.textSaveTapped("two"))
        await store.send(.previewDismissed) {
            $0.previewItem = nil
            $0.textContent = nil
            $0.textPhase = .idle
        }
        await store.send(.rowTapped(notes)) {
            $0.previewItem = notes
            $0.textPhase = .loading
        }
        await store.receive(\.textContentResponse.success) {
            $0.textPhase = .loaded
            $0.textContent = "on the server"
        }
        await store.send(.textSaveTapped("three"))
        gate.open()
        await store.receive(\.textSaveResponse) {
            $0.savingTexts = [:]
            $0.textContent = "one"
        }
        #expect(saves.value == ["one"])
    }

    @Test("A second file can be saved while the first save is still answering")
    func aSecondFileCanBeSavedWhileTheFirstSaveIsStillAnswering() async {
        let gate = AsyncGate()
        let saved = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(editingState()) {
            $0.filesClient.saveTextContent = { _, path, _ in
                saved.withValue { $0.append(path) }
                if path == notes.id {
                    try await gate.wait()
                }
            }
            $0.filesClient.fetchTextContent = { _, _ in "other" }
        }

        await store.send(.textSaveTapped("one")) {
            $0.savingTexts[notes.id] = "one"
        }
        await store.send(.previewDismissed) {
            $0.previewItem = nil
            $0.textContent = nil
            $0.textPhase = .idle
        }
        await store.send(.rowTapped(other)) {
            $0.previewItem = other
            $0.textPhase = .loading
        }
        await store.receive(\.textContentResponse.success) {
            $0.textPhase = .loaded
            $0.textContent = "other"
        }
        await store.send(.textSaveTapped("two")) {
            $0.savingTexts[other.id] = "two"
        }
        #expect(store.state.isSavingTextContent)
        await store.receive(\.textSaveResponse) {
            $0.savingTexts[other.id] = nil
            $0.textContent = "two"
        }
        gate.open()
        await store.receive(\.textSaveResponse) {
            $0.savingTexts = [:]
        }
        #expect(Set(saved.value) == [TestPath.docsNotes, "Docs/other.txt"])
    }

    @Test("Opening another file never cancels the save of the first")
    func openingAnotherFileNeverCancelsTheSaveOfTheFirst() async {
        let gate = AsyncGate()
        let finished = LockIsolated(false)
        let store = BrowseFixtures.store(editingState()) {
            $0.filesClient.saveTextContent = { _, _, _ in
                try await gate.wait()
                finished.setValue(true)
            }
            $0.filesClient.fetchTextContent = { _, _ in "other" }
        }

        await store.send(.textSaveTapped("one")) {
            $0.savingTexts[notes.id] = "one"
        }
        await store.send(.rowTapped(other)) {
            $0.previewItem = other
            $0.textContent = nil
            $0.textPhase = .loading
        }
        await store.receive(\.textContentResponse.success) {
            $0.textPhase = .loaded
            $0.textContent = "other"
        }
        gate.open()
        await store.receive(\.textSaveResponse) {
            $0.savingTexts = [:]
        }
        #expect(finished.value)
    }

    // MARK: Editor conflicts

    @Test("A file changed on the server prompts instead of saving")
    func aFileChangedOnTheServerPromptsInsteadOfSaving() async {
        let store = conflictStore()

        await saveIntoAConflict(store)
        #expect(store.state.isTextSaveConflictPresented)
    }

    @Test("Overwrite resends the edited text and clears the conflict")
    func overwriteResendsTheEditedTextAndClearsTheConflict() async {
        let attempts = LockIsolated(0)
        let sent = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(editingState()) {
            $0.filesClient.saveTextContent = { _, _, content in
                sent.withValue { $0.append(content) }
                let attempt = attempts.withValue { value -> Int in
                    value += 1
                    return value
                }
                if attempt == 1 {
                    throw FilesClientError.changedOnServer
                }
            }
        }

        await saveIntoAConflict(store)
        await store.send(.textSaveOverwriteTapped) {
            $0.textSaveConflict = nil
            $0.textSaveError = nil
            $0.savingTexts[notes.id] = "mine"
        }
        await store.receive(\.textSaveResponse) {
            $0.savingTexts = [:]
            $0.textContent = "mine"
        }
        #expect(sent.value == ["mine", "mine"])
    }

    @Test("Cancelling the conflict prompt asks again on the next save without touching the server")
    func cancellingTheConflictPromptAsksAgainOnTheNextSaveWithoutTouchingTheServer() async {
        let attempts = LockIsolated(0)
        let store = conflictStore {
            $0.filesClient.saveTextContent = { _, _, _ in
                attempts.withValue { $0 += 1 }
                throw FilesClientError.changedOnServer
            }
        }

        await saveIntoAConflict(store)
        await store.send(.textSaveConflictDismissed) {
            $0.textSaveConflict?.isAlertPresented = false
            $0.textSaveError = nil
        }
        await store.send(.textSaveTapped("mine again")) {
            $0.textSaveConflict = BrowseFeature.State.TextSaveConflict(pendingText: "mine again")
        }
        #expect(attempts.value == 1)
    }

    @Test("Reload fetches the server copy and drops the conflict")
    func reloadFetchesTheServerCopyAndDropsTheConflict() async {
        let store = conflictStore {
            $0.filesClient.fetchTextContent = { _, _ in "theirs" }
        }

        await saveIntoAConflict(store)
        await store.send(.textSaveReloadTapped) {
            $0.textContent = nil
            $0.textSaveError = nil
            $0.textSaveConflict = nil
            $0.textPhase = .loading
        }
        await store.receive(\.textContentResponse.success) {
            $0.textPhase = .loaded
            $0.textContent = "theirs"
        }
    }
}
