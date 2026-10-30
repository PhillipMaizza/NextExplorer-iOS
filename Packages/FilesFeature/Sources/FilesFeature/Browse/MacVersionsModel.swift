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

        /// Older servers have no versions route; `history` stays nil and the section hidden.
        func load(item: FileItem, serverURL: URL) async {
            self.item = item
            self.serverURL = serverURL
            history = nil
            errorMessage = nil
            guard !item.isDirectory else { return }
            let loaded = try? await filesClient.fetchVersions(serverURL, item.id)
            guard !Task.isCancelled, self.item?.id == item.id else { return }
            history = loaded
        }

        func restoreConfirmed() {
            guard let version = versionToRestore else { return }
            versionToRestore = nil
            perform(changesFiles: true) { client, serverURL, path in
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

        func renameConfirmed() {
            guard let version = versionToRename else { return }
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

        func deleteConfirmed() {
            guard let version = versionToDelete else { return }
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

        private func perform(
            changesFiles: Bool = false,
            _ operation: @escaping @Sendable (FilesClient, URL, String) async throws -> Void
        ) {
            guard let serverURL, let item else { return }
            let client = filesClient
            Task {
                do {
                    try await operation(client, serverURL, item.id)
                    errorMessage = nil
                    history = try? await client.fetchVersions(serverURL, item.id)
                    if changesFiles {
                        onFilesChanged()
                    }
                } catch {
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
                .alert(L10n.FileInfo.restoreTitle, isPresented: isPresented(\.versionToRestore)) {
                    Button(L10n.FileInfo.restoreConfirm) { model.restoreConfirmed() }
                    Button(L10n.Common.cancel, role: .cancel) {}
                } message: {
                    if let version = model.versionToRestore {
                        Text(L10n.FileInfo.restoreMessage(MacVersionsModel.date(version.modifiedAt)))
                    }
                }
                .alert(L10n.FileInfo.renameTitle, isPresented: isPresented(\.versionToRename)) {
                    TextField(L10n.FileInfo.renamePlaceholder, text: $model.renameDraft)
                    Button(L10n.Common.save) { model.renameConfirmed() }
                    Button(L10n.Common.cancel, role: .cancel) {}
                }
                .alert(L10n.FileInfo.deleteTitle, isPresented: isPresented(\.versionToDelete)) {
                    Button(L10n.Common.delete, role: .destructive) { model.deleteConfirmed() }
                    Button(L10n.Common.cancel, role: .cancel) {}
                } message: {
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
