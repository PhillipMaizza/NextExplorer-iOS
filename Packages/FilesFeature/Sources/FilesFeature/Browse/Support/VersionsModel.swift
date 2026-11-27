#if os(macOS)
    import AppKit
#endif
import ComposableArchitecture
import CoreModels
import Dependencies
import DesignSystem
import FilesClient
import FolderPickerFeature
import Localization
import Observation
import SwiftUI

/// One file's version history in Get Info, and what the Versions section can do with it:
/// restore, download, save as a copy, rename, keep, delete. Each change reloads the history.
@MainActor
@Observable
final class VersionsModel {
    private(set) var histories: [FileItem.ID: FileVersionHistory] = [:]
    private(set) var isServerEnabled = false
    var errorMessage: String?
    /// What the last change did, shown under the versions until the next one.
    var statusMessage: String?
    var versionToRestore: FileVersion?
    var restoreTarget: FileItem?
    var revealRequest: FileItem.ID?
    var versionToDelete: FileVersion?
    var versionToRename: FileVersion?
    var renameDraft = ""
    /// The version being read as text, shown in a sheet.
    var textPreview: VersionTextPreview?
    /// The file chooser open for "Replace Another File", `nil` otherwise.
    var replacePicker: StoreOf<DestinationPickerFeature>?
    /// A version and the file picked to receive it, asked about before anything is written.
    var replacement: VersionReplacement?
    var isConfirmingDeleteAll = false
    #if os(iOS)
        var sharedDownload: KeptFilesShare?
    #endif

    @ObservationIgnored @Dependency(\.filesClient) private var filesClient
    @ObservationIgnored private var serverURL: URL?
    @ObservationIgnored private var account: String?
    @ObservationIgnored private var featuresServerURL: URL?
    private var item: FileItem?
    /// After a change that touches the file or its folder, so the listing refreshes.
    @ObservationIgnored var onFilesChanged: () -> Void = {}
    @ObservationIgnored var onMenuFailure: (String) -> Void = { _ in }

    var history: FileVersionHistory? {
        item.flatMap { histories[$0.id] }
    }

    func history(for item: FileItem) -> FileVersionHistory? {
        histories[item.id]
    }

    func load(item: FileItem, serverURL: URL, account: String, settle: Duration = .zero) async {
        if self.serverURL != serverURL || self.account != account {
            histories = [:]
            featuresServerURL = nil
        }
        self.item = item
        self.serverURL = serverURL
        self.account = account
        errorMessage = nil
        statusMessage = nil
        guard !item.isDirectory else { return }
        if settle > .zero {
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled else { return }
        }
        if featuresServerURL != serverURL, let features = try? await filesClient.serverFeatures(serverURL) {
            featuresServerURL = serverURL
            isServerEnabled = features.isVersionsEnabled
        }
        guard !Task.isCancelled, let loaded = try? await filesClient.fetchVersions(serverURL, item.id),
              self.serverURL == serverURL, self.account == account else { return }
        isServerEnabled = loaded.isEnabled
        histories[item.id] = loaded
    }

    func menuPhase(for item: FileItem) -> VersionsMenuPhase {
        guard !item.isDirectory, isServerEnabled else { return .hidden }
        guard let history = histories[item.id] else { return item.id == self.item?.id ? .loading : .unloaded }
        return history.rights.canSee ? .loaded(history) : .hidden
    }

    func beginRestore(_ version: FileVersion, of item: FileItem) {
        restoreTarget = item
        versionToRestore = version
    }

    private static let textCharacterLimit = 200_000

    /// Whether versions of this file can be read as text: the editor's own list of text files.
    var canViewText: Bool {
        item.map { EditableTextFiles.isEditable(name: $0.name) } ?? false
    }

    /// Reads a version as text and opens it in a sheet. Nothing on the server changes.
    @discardableResult
    func viewText(_ version: FileVersion) -> Task<Void, Never>? {
        guard let serverURL, let item else { return nil }
        let client = filesClient
        statusMessage = nil
        return Task {
            do {
                let text = try await client.versionText(serverURL, item.id, version.id)
                guard self.item?.id == item.id else { return }
                errorMessage = nil
                let title = version.label ?? Self.date(text.modifiedAt)
                // One huge `Text` would stall the main thread, so only the start is shown.
                let head = text.content.prefix(Self.textCharacterLimit)
                textPreview = VersionTextPreview(
                    id: version.id,
                    title: title,
                    content: String(head),
                    isTruncated: head.endIndex != text.content.endIndex
                )
            } catch {
                noteSessionExpiry(error)
                guard self.item?.id == item.id else { return }
                errorMessage = (error as? FilesClientError)?.userMessage ?? error.localizedDescription
            }
        }
    }

    /// Opens the file chooser, starting in the file's own folder, to pick what the version replaces.
    func beginReplace(_ version: FileVersion) {
        guard let serverURL, let item else { return }
        replacePicker = Store(initialState: DestinationPickerFeature.State(serverURL: serverURL, replacing: item)) {
            VersionReplacePicker { [weak self] delegate in
                self?.pickerFinished(delegate, version: version)
            }
        }
    }

    func pickerFinished(_ delegate: DestinationPickerFeature.Action.Delegate, version: FileVersion) {
        replacePicker = nil
        if case let .confirmed(destination) = delegate {
            replacement = VersionReplacement(version: version, targetPath: destination)
        }
    }

    @discardableResult
    func replaceConfirmed(_ replacement: VersionReplacement) -> Task<Void, Never>? {
        self.replacement = nil
        let name = (replacement.targetPath as NSString).lastPathComponent
        return perform(
            changesFiles: true,
            success: L10n.FileInfo.versionReplaced(name)
        ) { client, serverURL, path in
            try await client.replaceWithVersion(serverURL, path, replacement.version.id, replacement.targetPath)
        }
    }

    /// The confirmations hand their version in: an alert may clear its binding before the
    /// button's action runs.
    @discardableResult
    func restoreConfirmed(_ version: FileVersion) -> Task<Void, Never>? {
        versionToRestore = nil
        let target = restoreTarget
        restoreTarget = nil
        return perform(on: target, changesFiles: true) { client, serverURL, path in
            try await client.restoreVersion(serverURL, path, version.id)
        }
    }

    @discardableResult
    func saveCopy(_ version: FileVersion, of target: FileItem? = nil) -> Task<Void, Never>? {
        guard let folder = (target ?? item)?.path else { return nil }
        return perform(on: target, changesFiles: true) { client, serverURL, path in
            _ = try await client.copyVersion(serverURL, path, version.id, folder)
        }
    }

    func beginRename(_ version: FileVersion) {
        renameDraft = version.label ?? ""
        versionToRename = version
    }

    func renameConfirmed(_ version: FileVersion) {
        versionToRename = nil
        let label = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        perform { client, serverURL, path in
            _ = try await client.updateVersion(serverURL, path, version.id, label, nil)
        }
    }

    @discardableResult
    func togglePin(_ version: FileVersion) -> Task<Void, Never>? {
        perform { client, serverURL, path in
            _ = try await client.updateVersion(serverURL, path, version.id, nil, !version.isPinned)
        }
    }

    func deleteConfirmed(_ version: FileVersion) {
        versionToDelete = nil
        perform { client, serverURL, path in
            try await client.deleteVersions(serverURL, path, [version.id], false)
        }
    }

    func deleteAllConfirmed() {
        isConfirmingDeleteAll = false
        perform { client, serverURL, path in
            try await client.deleteVersions(serverURL, path, [], true)
        }
    }

    // Asks where to save, named like the server names a copy, then downloads the version there.
    #if os(macOS)
        func download(_ version: FileVersion, of target: FileItem? = nil) {
            guard let file = target ?? item else { return }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = Self.copyName(for: file.name, version: version)
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            perform(on: target) { client, serverURL, path in
                try await client.downloadVersion(serverURL, path, version.id, destination)
            }
        }
    #else
        @discardableResult
        func download(_ version: FileVersion, of target: FileItem? = nil) -> Task<Void, Never>? {
            guard let file = target ?? item else { return nil }
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(Self.copyName(for: file.name, version: version))
            return perform(on: target) { [weak self] client, serverURL, path in
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try await client.downloadVersion(serverURL, path, version.id, destination)
                await self?.share(destination)
            }
        }

        func shareFinished() {
            if let url = sharedDownload?.urls.first {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
            sharedDownload = nil
        }

        private func share(_ url: URL) {
            sharedDownload = KeptFilesShare(urls: [url])
        }
    #endif

    /// Runs one change, then reloads the history. The task is handed back for tests to await.
    @discardableResult
    private func perform(
        on target: FileItem? = nil,
        changesFiles: Bool = false,
        success: String? = nil,
        _ operation: @escaping @Sendable (FilesClient, URL, String) async throws -> Void
    ) -> Task<Void, Never>? {
        guard let serverURL, let file = target ?? item else { return nil }
        let account = account
        let isFromMenu = target != nil
        let client = filesClient
        let onFilesChanged = onFilesChanged
        statusMessage = nil
        return Task {
            do {
                try await operation(client, serverURL, file.id)
                if changesFiles {
                    onFilesChanged()
                }
                let refreshed = try? await client.fetchVersions(serverURL, file.id)
                guard self.serverURL == serverURL, self.account == account else { return }
                if let refreshed {
                    histories[file.id] = refreshed
                }
                guard self.item?.id == file.id else { return }
                errorMessage = nil
                statusMessage = success
            } catch {
                noteSessionExpiry(error)
                let message = (error as? FilesClientError)?.userMessage ?? error.localizedDescription
                if isFromMenu {
                    onMenuFailure(message)
                } else if self.item?.id == file.id {
                    errorMessage = message
                }
            }
        }
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// The file name with the capture date and time appended, like the server's own name for a copy.
    private static func copyName(for fileName: String, version: FileVersion) -> String {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        let stamp = version.modifiedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let name = "\(base) (\(stamp))"
        return ext.isEmpty ? name : "\(name).\(ext)"
    }
}

enum VersionsMenuPhase: Equatable {
    case hidden
    case unloaded
    case loading
    case loaded(FileVersionHistory)
}

/// A version going into another file, ready to confirm.
struct VersionReplacement: Equatable {
    let version: FileVersion
    let targetPath: String
}

/// The file chooser's own reducer plus a hook that hands its answer to the versions model.
private struct VersionReplacePicker: Reducer {
    typealias State = DestinationPickerFeature.State
    typealias Action = DestinationPickerFeature.Action

    let onFinish: @MainActor @Sendable (DestinationPickerFeature.Action.Delegate) -> Void

    var body: some ReducerOf<Self> {
        DestinationPickerFeature()
        Reduce { _, action in
            guard case let .delegate(delegate) = action else { return .none }
            return .run { _ in await onFinish(delegate) }
        }
    }
}

/// One version's text, ready for the sheet.
struct VersionTextPreview: Identifiable, Equatable {
    let id: String
    let title: String
    let content: String
    let isTruncated: Bool
}
