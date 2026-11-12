import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct BrowseInfoAndPermissionsTests {
    private let photos = BrowseFixtures.folder("Photos")

    private func metadata(_ item: FileItem, size: Int64 = 0) -> FileMetadata {
        FileMetadata(
            path: item.id,
            name: item.name,
            kind: item.kind,
            size: size,
            dateModified: MockDate.date.addingTimeInterval(100),
            dateCreated: MockDate.date
        )
    }

    // MARK: Get Info

    @Test("Info on a folder fetches its metadata and the server's disk usage for its path")
    func infoTappedOnAFolderFetchesMetadataAndServerDiskUsage() async {
        let photosMetadata = metadata(photos, size: 4_096)
        let usage = StorageUsage(path: "Photos", size: 30, free: 70, total: 100)
        let usageGate = AsyncGate()
        let usagePaths = LockIsolated<[String]>([])
        let store = BrowseFixtures.store {
            $0.filesClient.fetchMetadata = { _, _ in photosMetadata }
            $0.filesClient.fetchUsage = { _, path in
                usagePaths.withValue { $0.append(path) }
                try await usageGate.wait()
                return usage
            }
        }

        await store.send(.infoTapped(photos)) {
            $0.infoItem = photos
            $0.infoPhase = .loading
        }
        await store.receive(\.infoMetadataResponse.success) {
            $0.infoPhase = .loaded
            $0.infoMetadata = photosMetadata
        }
        usageGate.open()
        await store.receive(\.infoUsageResponse.success) {
            $0.infoUsage = usage
        }
        #expect(usagePaths.value == ["Photos"])
    }

    @Test("Info on a file fetches its metadata and skips the disk usage")
    func infoTappedOnAFileSkipsTheUsageFetch() async {
        let notes = BrowseFixtures.file("notes.txt", size: 12)
        let notesMetadata = metadata(notes, size: 12)
        let store = BrowseFixtures.store {
            $0.filesClient.fetchMetadata = { _, _ in notesMetadata }
            $0.filesClient.fetchUsage = { _, _ in
                Issue.record("a file's Get Info should not fetch disk usage")
                return StorageUsage()
            }
        }

        await store.send(.infoTapped(notes)) {
            $0.infoItem = notes
            $0.infoPhase = .loading
        }
        await store.receive(\.infoMetadataResponse.success) {
            $0.infoPhase = .loaded
            $0.infoMetadata = notesMetadata
        }
    }

    @Test("A usage answer of all zeros is dropped, so the server disk section stays hidden")
    func anAllZeroUsageResponseIsDropped() async {
        var state = BrowseFixtures.state()
        state.infoUsage = StorageUsage(path: "x", size: 1, free: 1, total: 2)
        let store = BrowseFixtures.store(state)

        await store.send(.infoUsageResponse(.success(StorageUsage(path: "Photos", size: 0, free: 0, total: 0)))) {
            $0.infoUsage = nil
        }
    }

    @Test("A failed metadata fetch shows a readable message")
    func infoTappedFailureSurfacesAReadableErrorMessage() async {
        let notes = BrowseFixtures.file("notes.txt")
        let store = BrowseFixtures.store {
            $0.filesClient.fetchMetadata = { _, _ in throw FilesClientError.server(statusCode: 403) }
        }

        await store.send(.infoTapped(notes)) {
            $0.infoItem = notes
            $0.infoPhase = .loading
        }
        await store.receive(\.infoMetadataResponse.failure) {
            $0.infoPhase = .failed(FilesClientError.server(statusCode: 403).userMessage)
        }
    }

    @Test("Info on another item replaces the one showing, dropping its metadata, usage and error")
    func infoTappedOnADifferentItemWhileOneIsAlreadyShowingReplacesIt() async {
        let documents = BrowseFixtures.folder("Documents")
        let documentsMetadata = metadata(documents)
        var state = BrowseFixtures.state()
        state.infoItem = photos
        state.infoMetadata = metadata(photos)
        state.infoUsage = StorageUsage(path: "Photos", size: 1, free: 1, total: 2)
        state.infoPhase = .failed("stale error")
        let usageGate = AsyncGate()
        let store = BrowseFixtures.store(state) {
            $0.filesClient.fetchMetadata = { _, _ in documentsMetadata }
            $0.filesClient.fetchUsage = { _, _ in
                try await usageGate.wait()
                return StorageUsage()
            }
        }

        await store.send(.infoTapped(documents)) {
            $0.infoItem = documents
            $0.infoMetadata = nil
            $0.infoUsage = nil
            $0.infoPhase = .loading
        }
        await store.receive(\.infoMetadataResponse.success) {
            $0.infoPhase = .loaded
            $0.infoMetadata = documentsMetadata
        }
        usageGate.open()
        // All zeros: dropped, so the usage stays empty.
        await store.receive(\.infoUsageResponse.success)
    }

    @Test("Dismissing the info clears every part of its state")
    func infoDismissedClearsAllInfoState() async {
        var state = BrowseFixtures.state()
        state.infoItem = photos
        state.infoMetadata = metadata(photos)
        state.infoUsage = StorageUsage(path: "Photos", size: 1, free: 1, total: 2)
        state.infoPhase = .failed("some error")
        let store = BrowseFixtures.store(state)

        await store.send(.infoDismissed) {
            $0.infoItem = nil
            $0.infoMetadata = nil
            $0.infoUsage = nil
            $0.infoPhase = .idle
        }
    }

    // MARK: Permissions

    @Test("Permissions presents the sheet for the item, and dismissing it clears it")
    func permissionsTappedPresentsTheSheetSeededFromTheItemAndDismissClearsIt() async {
        let report = BrowseFixtures.file("report.pdf", in: "Documents", size: 10)
        let store = BrowseFixtures.store()

        await store.send(.permissionsTapped(report)) {
            $0.permissions = PermissionsFeature.State(serverURL: BrowseTestSupport.serverURL, item: report)
        }
        await store.send(.permissions(.dismiss)) {
            $0.permissions = nil
        }
    }
}
