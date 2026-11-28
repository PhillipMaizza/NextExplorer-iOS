import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import ShareUploads
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct MainTabUploadsTests: MainTabTestSupport {
    @Test("An upload requested from Browse enters the app wide queue and runs against its destination")
    func uploadRequestedFromBrowseEnqueuesIntoTheAppWideQueue() async throws {
        let file = PendingUpload(
            id: UUID(0),
            fileURL: URL(fileURLWithPath: "/tmp/a.txt"),
            fileName: TestFile.aText,
            destination: TestFolder.inbox
        )
        let uploaded = LockIsolated<[String]>([])
        let started = AsyncGate()
        let store = makeStore {
            $0.filesClient.uploadFile = { _, url, name, destination, _ in
                uploaded.withValue { $0.append("\(url.path) \(name) \(destination)") }
                started.open()
                try await suspendUntilCancelled()
                throw CancellationError()
            }
        }

        await store.send(.browse(.delegate(.uploadRequested([file]))))
        await store.receive(\.uploads.enqueue) {
            $0.uploads.jobs = [UploadsFeature.UploadJob(
                id: UUID(0), fileURL: URL(fileURLWithPath: "/tmp/a.txt"), fileName: TestFile.aText,
                destination: TestFolder.inbox, progress: 0, status: .queued
            )]
        }
        await store.receive(\.uploads.startNextIfIdle) {
            $0.uploads.jobs[id: UUID(0)]?.status = .uploading
            $0.uploads.jobs[id: UUID(0)]?.startedAt = MockDate.date
        }
        try await started.wait()
        await store.send(.uploads(.cancelAllTapped)) {
            $0.uploads.jobs = []
        }
        await store.finish()
        #expect(uploaded.value == ["/tmp/a.txt a.txt Inbox"])
    }

    @Test("A finished upload to another folder toasts with an Open action that jumps there")
    func queueFinishedShowsTheCompletionToastWithAnOpenActionForAnotherFolder() async {
        let store = makeStore()
        let summary = UploadsFeature.FinishSummary(
            uploadedCount: 2, failedCount: 0, lastDestination: TestPath.documentsReports,
            changedPaths: [TestPath.documentsReports]
        )

        await store.send(.uploads(.delegate(.queueFinished(summary)))) {
            $0.uploadToast = MainTabFeature.UploadToast(
                message: L10n.Uploads.completeMany(2),
                openDestination: TestPath.documentsReports
            )
        }
        await store.receive(\.browse.refreshDirectory)
        await store.receive(\.sharedBrowse.refreshDirectory)
        await store.receive(\.favorites.refreshDirectory)
        await store.receive(\.offline.uploadsLanded)
        await store.send(.openUploadedLocation(TestPath.documentsReports)) {
            $0.uploadToast = nil
            $0.selectedTab = .browse
        }
        await store.receive(\.browse.navigateToDirectory) {
            $0.browse.path[id: 0] = BrowseFeature.State(
                serverURL: serverURL,
                directoryPath: TestPath.documentsReports,
                title: "Reports"
            )
            $0.recentFolders = [TestPath.documentsReports]
        }
    }

    @Test("A finished upload into the folder already on screen toasts without an Open action and refetches it")
    func queueFinishedHidesTheOpenActionWhenAlreadyViewingThatFolder() async {
        let state = makeState {
            $0.browse.root = BrowseFeature.State(
                serverURL: serverURL,
                directoryPath: TestFolder.inbox,
                title: TestFolder.inbox
            )
        }
        let store = makeStore(state) { $0.serveEmptyFolders() }
        let summary = UploadsFeature.FinishSummary(
            uploadedCount: 1, failedCount: 0, lastDestination: TestFolder.inbox, changedPaths: [TestFolder.inbox]
        )

        await store.send(.uploads(.delegate(.queueFinished(summary)))) {
            $0.uploadToast = MainTabFeature.UploadToast(message: L10n.Uploads.complete, openDestination: nil)
        }
        await store.receive(\.browse.refreshDirectory)
        await store.receive(\.sharedBrowse.refreshDirectory)
        await store.receive(\.favorites.refreshDirectory)
        await store.receive(\.offline.uploadsLanded)
        await store.receive(\.browse.root.refreshButtonTapped) {
            $0.browse.root.phase = .loading
        }
        await store.receive(\.browse.root.itemsResponse.success) {
            $0.browse.root.phase = .loaded
            $0.browse.root.access = BrowseTestSupport.readOnlyAccess
        }
        await store.receive(\.browse.root.favoritesResponse) {
            $0.browse.root.hasLoadedFavorites = true
        }
    }

    @Test("A finished upload into a folder nobody is looking at refetches nothing")
    func queueFinishedRefreshesOnlyTheChangedFolderThatIsOnScreen() async {
        let state = makeState {
            $0.browse.root = BrowseFeature.State(
                serverURL: serverURL,
                directoryPath: TestFolder.inbox,
                title: TestFolder.inbox
            )
        }
        let store = makeStore(state)
        let summary = UploadsFeature.FinishSummary(
            uploadedCount: 1, failedCount: 0, lastDestination: "Archive/2026", changedPaths: ["Archive/2026"]
        )

        await store.send(.uploads(.delegate(.queueFinished(summary)))) {
            $0.uploadToast = MainTabFeature.UploadToast(message: L10n.Uploads.complete, openDestination: "Archive/2026")
        }
        await store.receive(\.browse.refreshDirectory)
        await store.receive(\.sharedBrowse.refreshDirectory)
        await store.receive(\.favorites.refreshDirectory)
        await store.receive(\.offline.uploadsLanded)
    }

    @Test("Big files the Share Extension kept are queued when the app comes forward")
    func appBecameActiveQueuesTheFilesTheExtensionKept() async throws {
        let kept = DeferredUpload(
            id: UUID(0).uuidString, accountID: "a", fileURL: URL(fileURLWithPath: "/tmp/big.txt"),
            fileName: TestFile.aText, destination: TestFolder.inbox
        )
        let asked = LockIsolated<[String]>([])
        let started = AsyncGate()
        let store = makeStore {
            $0.serveEmptyFolders()
            $0.shareUploads.pendingDeferred = { accountID in
                asked.withValue { $0.append(accountID) }
                return [kept]
            }
            $0.filesClient.uploadFile = { _, _, _, _, _ in
                started.open()
                try await suspendUntilCancelled()
                throw CancellationError()
            }
        }

        await store.send(.appBecameActive)
        await store.receive(\.browse.syncPathStack)
        await store.receive(\.sharedBrowse.syncPathStack)
        await store.receive(\.favorites.syncPathStack)
        await store.receive(\.uploads.appResumed)
        await store.receive(\.settings.loadPreferences)
        await store.receive(\.offline.autoSync)
        await store.receive(\.browse.root.refreshButtonTapped) {
            $0.browse.root.phase = .loading
        }
        await store.receive(\.uploads.enqueue) {
            $0.uploads.jobs = [UploadsFeature.UploadJob(
                id: UUID(0), fileURL: kept.fileURL, fileName: TestFile.aText,
                destination: TestFolder.inbox, progress: 0, status: .queued
            )]
        }
        await store.receive(\.uploads.startNextIfIdle) {
            $0.uploads.jobs[id: UUID(0)]?.status = .uploading
            $0.uploads.jobs[id: UUID(0)]?.startedAt = MockDate.date
        }
        await store.receive(\.settings.preferencesResponse.success) {
            $0.settings.preferencesPhase = .loaded
        }
        await store.receive(\.browse.root.itemsResponse.success) {
            $0.browse.root.phase = .loaded
            $0.browse.root.access = BrowseTestSupport.readOnlyAccess
        }
        await store.receive(\.browse.root.favoritesResponse) {
            $0.browse.root.hasLoadedFavorites = true
        }
        try await started.wait()
        await store.send(.uploads(.cancelAllTapped)) {
            $0.uploads.jobs = []
        }
        await store.finish()
        #expect(asked.value == [store.state.settings.uploadDefaults.accountID])
    }
}
