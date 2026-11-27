import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation
import Localization
import NetworkClient

@Reducer
struct ArchiveBrowserFeature {
    @ObservableState
    struct State: Equatable {
        let archive: FileItem
        let serverURL: URL
        var source: Source
        var path: [String] = []
        var levels: [String: [ArchiveListingEntry]] = [:]
        var phase: DataPhase = .idle
        var entry: OpenedEntry?

        init(archive: FileItem, serverURL: URL, localFileURL: URL? = nil) {
            self.archive = archive
            self.serverURL = serverURL
            source = localFileURL.map(Source.local) ?? .unresolved
        }

        var inside: String {
            path.joined(separator: "/")
        }

        var entries: [ArchiveListingEntry] {
            levels[inside] ?? []
        }

        var files: [ArchiveListingEntry] {
            entries.filter { !$0.isDirectory }
        }

        var openedIndex: Int? {
            entry.flatMap { opened in files.firstIndex { $0.path == opened.path } }
        }

        var crumbs: [String] {
            [archive.name] + path + (entry.map { [($0.path as NSString).lastPathComponent] } ?? [])
        }

        var isAtRoot: Bool {
            path.isEmpty && entry == nil
        }

        var canExtract: Bool {
            source == .server && openedIndex.map { !files[$0].isEncrypted } ?? true
        }

        var extractPaths: [String]? {
            entry.map { [$0.path] } ?? (path.isEmpty ? nil : [inside])
        }
    }

    enum Source: Equatable, Sendable {
        case unresolved
        case server
        case local(URL)
    }

    struct OpenedEntry: Equatable {
        let path: String
        var phase: Phase

        enum Phase: Equatable {
            case loading
            case loaded(URL)
            case failed(String)
        }
    }

    struct Failure: Error, Equatable {
        let message: String
    }

    enum Action: Equatable {
        case task
        case sourceResolved(Result<Source, Failure>)
        case levelResponse(inside: String, Result<[ArchiveListingEntry], Failure>)
        case folderOpened(String)
        case crumbTapped(Int)
        case backTapped
        case fileOpened(ArchiveListingEntry)
        case stepped(Int)
        case entryResponse(path: String, Result<URL, Failure>)
        case retryTapped
        case closed
    }

    private enum CancelID {
        case source
        case level
        case entry
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.archiveReader) var archiveReader

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return start(&state)

            case let .sourceResolved(.success(source)):
                state.source = source
                return loadLevel(&state)

            case let .sourceResolved(.failure(failure)):
                state.phase = .failed(failure.message)
                return .none

            case let .levelResponse(inside, .success(entries)):
                state.levels[inside] = entries
                if inside == state.inside {
                    state.phase = .loaded
                }
                return .none

            case let .levelResponse(inside, .failure(failure)):
                guard inside == state.inside else { return .none }
                state.phase = .failed(failure.message)
                return .none

            case let .folderOpened(name):
                state.entry = nil
                state.path.append(name)
                return .merge(.cancel(id: CancelID.entry), loadLevel(&state))

            case let .crumbTapped(index):
                guard index <= state.path.count else { return .none }
                state.entry = nil
                state.path = Array(state.path.prefix(index))
                return .merge(.cancel(id: CancelID.entry), loadLevel(&state))

            case .backTapped:
                if state.entry != nil {
                    state.entry = nil
                    return .cancel(id: CancelID.entry)
                }
                guard !state.path.isEmpty else { return .none }
                state.path.removeLast()
                return loadLevel(&state)

            case let .fileOpened(file):
                guard !file.isDirectory else { return .send(.folderOpened(file.name)) }
                guard !file.isEncrypted else {
                    state.entry = OpenedEntry(path: file.path, phase: .failed(L10n.Archive.entryEncrypted))
                    return .cancel(id: CancelID.entry)
                }
                state.entry = OpenedEntry(path: file.path, phase: .loading)
                return openEntry(file, in: state)

            case let .stepped(offset):
                guard let index = state.openedIndex, state.files.indices.contains(index + offset) else {
                    return .none
                }
                return .send(.fileOpened(state.files[index + offset]))

            case let .entryResponse(path, result):
                guard state.entry?.path == path else { return .none }
                switch result {
                case let .success(url): state.entry?.phase = .loaded(url)
                case let .failure(failure): state.entry?.phase = .failed(failure.message)
                }
                return .none

            case .retryTapped:
                if let entry = state.entry, let file = state.files.first(where: { $0.path == entry.path }) {
                    return .send(.fileOpened(file))
                }
                state.levels[state.inside] = nil
                return state.source == .unresolved ? start(&state) : loadLevel(&state)

            case .closed:
                let cancels = Effect<Action>.merge(
                    .cancel(id: CancelID.source),
                    .cancel(id: CancelID.level),
                    .cancel(id: CancelID.entry)
                )
                guard case let .local(url) = state.source else { return cancels }
                return .merge(cancels, .run { [archiveReader] _ in await archiveReader.release(url) })
            }
        }
    }

    private func start(_ state: inout State) -> Effect<Action> {
        guard state.source == .unresolved else { return loadLevel(&state) }
        state.phase = .loading
        let archive = state.archive
        let serverURL = state.serverURL
        return .run { [filesClient] send in
            await send(.sourceResolved(Self.attempt {
                let extensions = try? await filesClient.serverFeatures(serverURL).archiveExtensions
                if extensions?.contains(archive.kind.lowercased()) == true {
                    return Source.server
                }
                return try await .local(filesClient.downloadRawFile(serverURL, archive))
            }))
        }
        .cancellable(id: CancelID.source, cancelInFlight: true)
    }

    private func loadLevel(_ state: inout State) -> Effect<Action> {
        let inside = state.inside
        guard state.levels[inside] == nil else {
            state.phase = .loaded
            return .cancel(id: CancelID.level)
        }
        state.phase = .loading
        let source = state.source
        let archive = state.archive
        let serverURL = state.serverURL
        return .run { [filesClient, archiveReader] send in
            await send(.levelResponse(inside: inside, Self.attempt {
                switch source {
                case .unresolved: []
                case .server: try await filesClient.listArchive(serverURL, archive, inside).entries
                case let .local(url): try await archiveReader.list(url, archive.kind, inside).entries
                }
            }))
        }
        .cancellable(id: CancelID.level, cancelInFlight: true)
    }

    private func openEntry(_ file: ArchiveListingEntry, in state: State) -> Effect<Action> {
        let source = state.source
        let archive = state.archive
        let serverURL = state.serverURL
        return .run { [filesClient, archiveReader] send in
            await send(.entryResponse(path: file.path, Self.attempt {
                guard let destination = SafeDestination.within(Self.scratchDirectory(for: archive), file.path) else {
                    throw Failure(message: L10n.Archive.openFailed)
                }
                switch source {
                case .unresolved:
                    throw Failure(message: L10n.Archive.openFailed)
                case .server:
                    let downloaded = try await filesClient.downloadArchiveEntry(serverURL, archive, file.path)
                    try Self.move(downloaded, to: destination)
                case let .local(url):
                    try await archiveReader.extract(url, archive.kind, file.path, destination)
                }
                return destination
            }))
        }
        .cancellable(id: CancelID.entry, cancelInFlight: true)
    }

    static func scratchDirectory(for archive: FileItem) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(SessionScratchLocation.archiveBrowser, isDirectory: true)
            .appendingPathComponent(archive.id.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
    }

    private static func move(_ downloaded: URL, to destination: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.removeItem(at: destination)
        try manager.moveItem(at: downloaded, to: destination)
    }

    private static func attempt<Value>(_ operation: () async throws -> Value) async -> Result<Value, Failure> {
        do {
            return try await .success(operation())
        } catch {
            return .failure(failure(for: error))
        }
    }

    static func failure(for error: any Error) -> Failure {
        if let failure = error as? Failure {
            return failure
        }
        if let readerError = error as? ArchiveReaderError {
            return Failure(message: readerError == .entryTooLarge
                ? L10n.Archive.entryTooLarge
                : L10n.Archive
                    .unreadable)
        }
        guard let filesError = error as? FilesClientError else {
            return Failure(message: L10n.Archive.openArchiveFailed)
        }
        noteSessionExpiry(filesError)
        let status: Int? = switch filesError {
        case let .server(code), let .serverMessage(code, _): code
        default: nil
        }
        return switch status {
        case HTTPStatus.conflict.rawValue: Failure(message: L10n.Archive.passwordProtected)
        case HTTPStatus.payloadTooLarge.rawValue: Failure(message: L10n.Archive.tooManyEntries)
        case HTTPStatus.unprocessableContent.rawValue: Failure(message: L10n.Archive.unreadable)
        default: Failure(message: filesError.userMessage)
        }
    }
}

extension ArchiveListingEntry {
    var fileItem: FileItem {
        FileItem(
            name: name,
            path: (path as NSString).deletingLastPathComponent,
            dateModified: .distantPast,
            size: size ?? 0,
            kind: kind
        )
    }
}
