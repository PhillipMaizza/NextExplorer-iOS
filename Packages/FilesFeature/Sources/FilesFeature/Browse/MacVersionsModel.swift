#if os(macOS)
    import AppKit
    import CoreModels
    import Dependencies
    import DesignSystem
    import FilesClient
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
        var versionToRestore: FileVersion?
        var versionToDelete: FileVersion?
        var versionToRename: FileVersion?
        var renameDraft = ""
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
            guard !item.isDirectory else { return }
            if settle > .zero {
                try? await Task.sleep(for: settle)
                guard !Task.isCancelled else { return }
            }
            let loaded = try? await filesClient.fetchVersions(serverURL, item.id)
            guard !Task.isCancelled, self.item?.id == item.id else { return }
            history = loaded
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

        func togglePin(_ version: FileVersion) {
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
            _ operation: @escaping @Sendable (FilesClient, URL, String) async throws -> Void
        ) -> Task<Void, Never>? {
            guard let serverURL, let item else { return nil }
            let client = filesClient
            let onFilesChanged = onFilesChanged
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
                    history = refreshed
                } catch {
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

    /// The Versions section's confirmations and rename prompt, attached to the inspector.
    struct MacVersionsDialogs: ViewModifier {
        @Bindable var model: MacVersionsModel

        func body(content: Content) -> some View {
            content
                .alert(L10n.FileInfo.restoreTitle, isPresented: isPresented(\.versionToRestore), presenting: model.versionToRestore) { version in
                    Button(L10n.FileInfo.restoreConfirm) { model.restoreConfirmed(version) }
                    Button(L10n.Common.cancel, role: .cancel) {}
                } message: { version in
                    Text(L10n.FileInfo.restoreMessage(MacVersionsModel.date(version.modifiedAt)))
                }
                .alert(L10n.FileInfo.renameTitle, isPresented: isPresented(\.versionToRename), presenting: model.versionToRename) { version in
                    TextField(L10n.FileInfo.renamePlaceholder, text: $model.renameDraft)
                    Button(L10n.Common.save) { model.renameConfirmed(version) }
                    Button(L10n.Common.cancel, role: .cancel) {}
                }
                .alert(L10n.FileInfo.deleteTitle, isPresented: isPresented(\.versionToDelete), presenting: model.versionToDelete) { version in
                    Button(L10n.Common.delete, role: .destructive) { model.deleteConfirmed(version) }
                    Button(L10n.Common.cancel, role: .cancel) {}
                } message: { _ in
                    Text(L10n.FileInfo.deleteMessage)
                }
                .alert(L10n.FileInfo.deleteAllTitle, isPresented: $model.isConfirmingDeleteAll) {
                    Button(L10n.Common.delete, role: .destructive) { model.deleteAllConfirmed() }
                    Button(L10n.Common.cancel, role: .cancel) {}
                } message: {
                    Text(L10n.FileInfo.deleteMessage)
                }
        }

        private func isPresented(_ keyPath: ReferenceWritableKeyPath<MacVersionsModel, FileVersion?>) -> Binding<Bool> {
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
