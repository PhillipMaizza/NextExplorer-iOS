import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// A versions list request a test recorded.
struct VersionedFilesPageCall: Equatable, Sendable {
    let filter: VersionedFilesFilter
    let offset: Int
    let limit: Int
}

/// A version deletion request a test recorded; `nil` versions means every version.
struct VersionedFilesDeleteCall: Equatable, Sendable {
    let fileID: String
    let versionIDs: [String]?
}

/// The builders the versions list suites share. Each suite owns its gate and recorders.
@MainActor
protocol VersionedFilesTestSupport {
    var pageGate: AsyncGate { get }
    var pageCalls: LockIsolated<[VersionedFilesPageCall]> { get }
    var detailCalls: LockIsolated<[String]> { get }
    var deleteCalls: LockIsolated<[VersionedFilesDeleteCall]> { get }
}

extension VersionedFilesTestSupport {
    typealias Store = TestStoreOf<VersionedFilesFeature>
    typealias State = VersionedFilesFeature.State

    var serverURL: URL {
        SettingsTestSupport.serverURL
    }

    func file(_ id: String, versions: Int = 2, state: VersionedFileState = .live) -> VersionedFile {
        VersionedFile(id: id, name: "\(id).txt", state: state, versions: versions, bytes: 100)
    }

    nonisolated static func version(_ id: String) -> FileVersion {
        FileVersion(id: id, size: 10, modifiedAt: MockDate.date, capturedAt: MockDate.date.addingTimeInterval(60))
    }

    func makeStore(
        _ state: State? = nil,
        page: @escaping @Sendable (VersionedFilesFilter, Int) async throws -> VersionedFilesPage = { _, _ in
            VersionedFilesPage()
        },
        detail: @escaping @Sendable (String) async throws -> VersionedFileDetail = { _ in VersionedFileDetail() },
        delete: @escaping @Sendable (String, [String]?) async throws -> VersionsDeletion = { _, _ in
            VersionsDeletion()
        }
    ) -> Store {
        let pageCalls = pageCalls
        let detailCalls = detailCalls
        let deleteCalls = deleteCalls
        return TestStore(initialState: state ?? State(serverURL: serverURL)) {
            VersionedFilesFeature()
        } withDependencies: {
            $0.filesClient.fetchVersionedFiles = { _, filter, offset, limit in
                pageCalls.withValue { $0.append(VersionedFilesPageCall(filter: filter, offset: offset, limit: limit)) }
                return try await page(filter, offset)
            }
            $0.filesClient.fetchVersionedFile = { _, id in
                detailCalls.withValue { $0.append(id) }
                return try await detail(id)
            }
            $0.filesClient.deleteVersionsOfFile = { _, id, ids in
                deleteCalls.withValue { $0.append(VersionedFilesDeleteCall(fileID: id, versionIDs: ids)) }
                return try await delete(id, ids)
            }
        }
    }

    /// A page answer that waits until the test opens `pageGate`, for the actions that start a
    /// page read and a history read side by side.
    func gatedPage(_ page: VersionedFilesPage)
        -> @Sendable (VersionedFilesFilter, Int) async throws -> VersionedFilesPage
    {
        let pageGate = pageGate
        return { _, _ in
            try await pageGate.wait()
            return page
        }
    }

    func loadedState(files: [VersionedFile] = [], total: Int? = nil, offset: Int = 0) -> State {
        var state = State(serverURL: serverURL)
        state.page = VersionedFilesPage(files: files, total: total ?? files.count, offset: offset)
        state.offset = offset
        state.phase = .loaded
        return state
    }

    /// The answer to the page read a reload started: it ends the reload and replaces the page.
    func receivePage(_ store: Store, _ page: VersionedFilesPage) async {
        await store.receive(.pageResponse(.success(page))) {
            $0.isReloading = false
            $0.page = page
        }
    }
}
