#if os(macOS)
    import AppKit
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
    final class MacVersionsModel {
        private(set) var history: FileVersionHistory?
        var errorMessage: String?
        /// What the last change did, shown under the versions until the next one.
        var statusMessage: String?
        var versionToRestore: FileVersion?
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

        @ObservationIgnored @Dependency(\.filesClient) private var filesClient
        @ObservationIgnored private var serverURL: URL?
        @ObservationIgnored private var item: FileItem?
        /// After a change that touches the file or its folder, so the listing refreshes.
        @ObservationIgnored var onFilesChanged: () -> Void = {}

        /// Older servers have no versions route; `history` stays nil and the section hidden. The
        /// previous file's history clears at once, so nothing acts on it during `settle`.
        func load(item: FileItem, serverURL: URL, settle: Duration = .zero) async {
            self.item = item
            self.serverURL = serverURL
            history = nil
            errorMessage = nil
            statusMessage = nil
            guard !item.isDirectory else { return }
            if settle > .zero {
                try? await Task.sleep(for: settle)
                guard !Task.isCancelled else { return }
            }
            let loaded = try? await filesClient.fetchVersions(serverURL, item.id)
            guard !Task.isCancelled, self.item?.id == item.id else { return }
            history = loaded
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
            return perform(changesFiles: true) { client, serverURL, path in
                try await client.restoreVersion(serverURL, path, version.id)
            }
        }

        func saveCopy(_ version: FileVersion) {
            guard let folder = item?.path else { return }
            perform(changesFiles: true) { client, serverURL, path in
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

        /// Asks where to save, named like the server names a copy, then downloads the version there.
        func download(_ version: FileVersion) {
            guard let item else { return }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = Self.copyName(for: item.name, version: version)
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            perform { client, serverURL, path in
                try await client.downloadVersion(serverURL, path, version.id, destination)
            }
        }

        /// Runs one change, then reloads the history. The task is handed back for tests to await.
        @discardableResult
        private func perform(
            changesFiles: Bool = false,
            success: String? = nil,
            _ operation: @escaping @Sendable (FilesClient, URL, String) async throws -> Void
        ) -> Task<Void, Never>? {
            guard let serverURL, let item else { return nil }
            let client = filesClient
            let onFilesChanged = onFilesChanged
            statusMessage = nil
            return Task {
                do {
                    try await operation(client, serverURL, item.id)
                    if changesFiles {
                        onFilesChanged()
                    }
                    let refreshed = try? await client.fetchVersions(serverURL, item.id)
                    // The selection may have moved on while this ran; never paint this file's
                    // history over the next one's.
                    guard self.item?.id == item.id else { return }
                    errorMessage = nil
                    statusMessage = success
                    history = refreshed
                } catch {
                    noteSessionExpiry(error)
                    guard self.item?.id == item.id else { return }
                    errorMessage = (error as? FilesClientError)?.userMessage ?? error.localizedDescription
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

    /// The Versions section's confirmations and rename prompt, attached to the inspector.
    struct MacVersionsDialogs: ViewModifier {
        @Bindable var model: MacVersionsModel

        func body(content: Content) -> some View {
            content
                .alert(
                    L10n.FileInfo.restoreTitle,
                    isPresented: isPresented(\.versionToRestore),
                    presenting: model.versionToRestore
                ) { version in
                    Button(L10n.FileInfo.restoreConfirm) { model.restoreConfirmed(version) }
                    Button(L10n.Common.cancel, role: .cancel) {}
                } message: { version in
                    Text(L10n.FileInfo.restoreMessage(MacVersionsModel.date(version.modifiedAt)))
                }
                .alert(
                    L10n.FileInfo.renameTitle,
                    isPresented: isPresented(\.versionToRename),
                    presenting: model.versionToRename
                ) { version in
                    TextField(L10n.FileInfo.renamePlaceholder, text: $model.renameDraft)
                    Button(L10n.Common.save) { model.renameConfirmed(version) }
                    Button(L10n.Common.cancel, role: .cancel) {}
                }
                .alert(
                    L10n.FileInfo.deleteTitle,
                    isPresented: isPresented(\.versionToDelete),
                    presenting: model.versionToDelete
                ) { version in
                    Button(L10n.Common.delete, role: .destructive) { model.deleteConfirmed(version) }
                    Button(L10n.Common.cancel, role: .cancel) {}
                } message: { _ in
                    Text(L10n.FileInfo.deleteMessage)
                }
                .sheet(isPresented: isPresented(\.replacePicker)) {
                    if let store = model.replacePicker {
                        DestinationPickerView(store: store)
                    }
                }
                .alert(
                    L10n.FileInfo.replaceTitle,
                    isPresented: isPresented(\.replacement),
                    presenting: model.replacement
                ) { replacement in
                    Button(L10n.Browse.transferConflictReplace) { model.replaceConfirmed(replacement) }
                    Button(L10n.Common.cancel, role: .cancel) {}
                } message: { replacement in
                    Text(L10n.FileInfo.replaceMessage(
                        (replacement.targetPath as NSString).lastPathComponent,
                        MacVersionsModel.date(replacement.version.modifiedAt)
                    ))
                }
                .sheet(item: $model.textPreview) { preview in
                    MacVersionTextSheet(preview: preview)
                }
                .alert(L10n.FileInfo.deleteAllTitle, isPresented: $model.isConfirmingDeleteAll) {
                    Button(L10n.Common.delete, role: .destructive) { model.deleteAllConfirmed() }
                    Button(L10n.Common.cancel, role: .cancel) {}
                } message: {
                    Text(L10n.FileInfo.deleteMessage)
                }
        }

        private func isPresented(_ keyPath: ReferenceWritableKeyPath<MacVersionsModel, (some Any)?>) -> Binding<Bool> {
            Binding(get: { model[keyPath: keyPath] != nil }, set: {
                if !$0 {
                    model[keyPath: keyPath] = nil
                }
            })
        }
    }

    #Preview("Delete all confirmation") {
        let model = MacVersionsModel()
        model.isConfirmingDeleteAll = true
        return Text(verbatim: "report.pdf")
            .previewCanvas(.inspector)
            .modifier(MacVersionsDialogs(model: model))
    }
#endif
