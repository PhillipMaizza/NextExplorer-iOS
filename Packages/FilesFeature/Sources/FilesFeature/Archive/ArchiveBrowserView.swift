import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

private enum Constants {
    static let rowSpacing: CGFloat = .space16
    static let backIconSize: CGFloat = .iconSmall
    static let rowIconSize: CGFloat = .iconMedium
    static let statusSpacing: CGFloat = .space16
}

/// One row of the current folder level within `ArchiveBrowserView` — directories are
/// synthesized from entry path prefixes (most archives don't include explicit directory
/// entries for every intermediate folder), not just the ones the archive lists directly.
private struct ArchiveRow: Identifiable {
    let name: String
    let isDirectory: Bool
    let size: UInt64?

    var id: String { "\(isDirectory ? "d" : "f")/\(name)" }
}

/// One in-archive file opened for preview, bundled with its extracted location and the row
/// name it grew from (the `.zoom` transition source).
private struct ArchiveEntryPreview: Identifiable, Equatable {
    let item: FileItem
    let fileURL: URL
    let sourceID: String

    var id: String { fileURL.path }
}

/// Result of a background entry extraction — `tooLarge` is split out so the user gets a
/// "too large to open" message rather than the generic open failure.
private enum ArchiveExtractionOutcome: Sendable {
    case success
    case tooLarge
    case failed
}

/// Full-screen client-side browser for `.zip`/`.rar` contents (`FileItem.isBrowsableArchive`)
/// — downloads the archive once via `FilesClient.downloadRawFile`, then navigates its entry
/// list like a real folder tree, entirely in memory. Google-Drive-style "open and see what's
/// inside," without the server ever fully extracting anything to disk. Files inside are
/// previewable the same way top-level files are — see `ArchiveEntryPreviewView`.
struct ArchiveBrowserView: View {
    let item: FileItem
    let serverURL: URL
    let onDismiss: () -> Void

    @State private var entries: [ArchiveEntry] = []
    @State private var source: ArchiveSource?
    @State private var currentPath: [String] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var previewingEntry: ArchiveEntryPreview?
    /// Name of the row whose entry is currently being extracted off the main thread — drives
    /// its trailing spinner and blocks a second concurrent extraction.
    @State private var extractingRow: String?
    @State private var toastMessage: DSToastMessage?
    /// Pairs each file row with its full-screen preview cover so it opens and interactively
    /// swipes-to-dismiss with the native `.zoom` morph, same as the browse tab.
    @Namespace private var entryTransition
    @Dependency(\.filesClient) private var filesClient

    private var visibleRows: [ArchiveRow] {
        let prefix = currentPath.isEmpty ? "" : currentPath.joined(separator: "/") + "/"
        var seenDirectoryNames = Set<String>()
        var rows: [ArchiveRow] = []
        for entry in entries {
            guard prefix.isEmpty || entry.path.hasPrefix(prefix) else { continue }
            let remainder = entry.path.dropFirst(prefix.count)
            guard !remainder.isEmpty else { continue }
            let components = remainder.split(separator: "/", omittingEmptySubsequences: true)
            guard let first = components.first else { continue }
            let name = String(first)
            if components.count == 1, !entry.isDirectory {
                rows.append(ArchiveRow(name: name, isDirectory: false, size: entry.size))
            } else if !seenDirectoryNames.contains(name) {
                seenDirectoryNames.insert(name)
                rows.append(ArchiveRow(name: name, isDirectory: true, size: nil))
            }
        }
        return rows.sorted { lhs, rhs in
            lhs.isDirectory != rhs.isDirectory
                ? lhs.isDirectory
                : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var title: String {
        currentPath.last ?? item.name
    }

    var body: some View {
        NavigationStack {
            content
                .backgroundGradient()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !currentPath.isEmpty {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                currentPath.removeLast()
                            } label: {
                                IconKit.back
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(Color.primaryDS)
                                    .frame(width: Constants.backIconSize, height: Constants.backIconSize)
                            }
                            .accessibilityLabel(L10n.Common.back)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { onDismiss() } label: {
                            IconKit.close.foregroundStyle(Color.primaryDS)
                        }
                        .accessibilityLabel(L10n.Common.close)
                    }
                }
        }
        .dsToast($toastMessage)
        // A real cover, nested inside the archive's own `.fullScreenCover` — the entry
        // preview morphs from its row and swipes back to it (`.zoom`), and dismissing it
        // lands back in the archive listing rather than closing everything.
        .fullScreenCover(item: $previewingEntry) { entry in
            PreviewZoomContainer(sourceID: entry.sourceID, namespace: entryTransition) {
                ArchiveEntryPreviewView(
                    item: entry.item,
                    fileURL: entry.fileURL,
                    serverURL: serverURL,
                    resolveAsset: { relativePath in await resolveAsset(relativePath, relativeTo: entry.item.path) },
                    onDismiss: { previewingEntry = nil }
                )
            }
        }
        .task {
            await load()
        }
        // Navigating a folder abandons any in-flight extraction the user walked away from.
        .onChange(of: currentPath) { _, _ in extractingRow = nil }
        // Closing the browser purges this archive's extracted entries and resolved assets from
        // `tmp` — otherwise the last opened entry of every archive ever browsed lingers there
        // until the OS purges under pressure. Skipped while an extraction is still running so we
        // never delete a file out from under an in-flight write.
        .onDisappear {
            guard extractingRow == nil else { return }
            let directory = Self.temporaryDirectory(for: item)
            Task.detached(priority: .utility) { [directory] in
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            statusContent(icon: IconKit.warning, message: errorMessage, tint: .negative)
        } else if isLoading {
            statusContent(icon: nil, message: nil, tint: .primaryDS)
        } else if visibleRows.isEmpty {
            statusContent(icon: IconKit.folderFill, message: L10n.Archive.emptyFolder, tint: .secondaryDS)
        } else {
            List(visibleRows) { row in
                Button {
                    handleTap(row)
                } label: {
                    rowContent(row)
                }
                .listRowBackground(Color.backgroundSecondary)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    private func rowContent(_ row: ArchiveRow) -> some View {
        HStack(spacing: Constants.rowSpacing) {
            if row.isDirectory {
                IconKit.folderFill
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.accent)
                    .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
            } else {
                FileTypeIcon(kind: (row.name as NSString).pathExtension)
                    .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
                    .matchedTransitionSource(id: row.name, in: entryTransition)
            }
            Text(row.name).type(.body2(.semibold), style: .primary(for: .label))
            Spacer()
            if extractingRow == row.name {
                DSSpinner(size: .small)
            } else if let size = row.size {
                Text(Self.byteFormatter.string(fromByteCount: Int64(size)))
                    .type(.body3(.regular), style: .secondary)
            }
            if row.isDirectory {
                IconKit.chevronRight
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: .iconXSmall, height: .iconXSmall)
            }
        }
    }

    private func statusContent(icon: Image?, message: String?, tint: Color) -> some View {
        VStack(spacing: Constants.statusSpacing) {
            if let icon, let message {
                icon
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tint)
                    .frame(width: .iconMedium, height: .iconMedium)
                Text(message).type(.body1(.regular), style: .secondary)
            } else {
                DSSpinner()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleTap(_ row: ArchiveRow) {
        guard !row.isDirectory else {
            currentPath.append(row.name)
            return
        }
        guard extractingRow == nil, let source else { return }
        let rowName = row.name
        let fullPath = currentPath.isEmpty ? rowName : currentPath.joined(separator: "/") + "/" + rowName
        let parent = (fullPath as NSString).deletingLastPathComponent
        let entryItem = FileItem(
            name: rowName,
            path: parent,
            dateModified: Date(timeIntervalSince1970: 0),
            size: Int64(row.size ?? 0),
            kind: (rowName as NSString).pathExtension
        )
        guard let destination = SafeDestination.within(Self.temporaryDirectory(for: item), rowName) else {
            toastMessage = DSToastMessage(icon: IconKit.warning, text: L10n.Archive.openFailed)
            return
        }
        extractingRow = rowName
        Task {
            // Off the main thread — a multi-gigabyte entry (a large video, or an unsupported
            // binary opened just to be shared) would otherwise freeze the UI while it unpacks.
            let outcome = await Task.detached(priority: .userInitiated) { () -> ArchiveExtractionOutcome in
                try? FileManager.default.removeItem(at: destination)
                try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                do {
                    try ArchiveReader.extract(fullPath, from: source, to: destination)
                    return .success
                } catch ArchiveReaderError.entryTooLarge {
                    try? FileManager.default.removeItem(at: destination)
                    return .tooLarge
                } catch {
                    return .failed
                }
            }.value
            // Bail if the user navigated away or tapped another row meanwhile.
            guard extractingRow == rowName else { return }
            extractingRow = nil
            switch outcome {
            case .success:
                previewingEntry = ArchiveEntryPreview(item: entryItem, fileURL: destination, sourceID: rowName)
            case .tooLarge:
                toastMessage = DSToastMessage(icon: IconKit.warning, text: L10n.Archive.entryTooLarge)
            case .failed:
                toastMessage = DSToastMessage(icon: IconKit.warning, text: L10n.Archive.openFailed)
            }
        }
    }

    /// Resolves and extracts a sibling asset referenced by an in-archive HTML/Markdown file
    /// (e.g. `style.css` next to `page.html`) from the same open archive — the archive
    /// equivalent of `TextFilePreviewView.resolveServerAsset`.
    private func resolveAsset(_ relativePath: String, relativeTo directory: String) async -> URL? {
        guard let source, let resolved = RelativeAssetPath.resolve(relativePath, relativeTo: directory) else { return nil }
        let entryPath = resolved.parent.isEmpty ? resolved.name : "\(resolved.parent)/\(resolved.name)"
        let assetsBase = Self.temporaryDirectory(for: item).appendingPathComponent("assets", isDirectory: true)
        guard let destination = SafeDestination.within(assetsBase, entryPath) else { return nil }
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        return (try? ArchiveReader.extract(entryPath, from: source, to: destination)) != nil ? destination : nil
    }

    private func load() async {
        do {
            let fileURL = try await filesClient.downloadRawFile(serverURL, item)
            let kind = item.kind
            // Opening the container and listing its entries parses the whole archive; keep both
            // off the main actor so a large or deeply nested archive does not freeze the UI on
            // open, matching the extract path below.
            let (opened, listed) = try await Task.detached(priority: .userInitiated) {
                let source = try ArchiveReader.open(fileURL: fileURL, kind: kind)
                return (source, try ArchiveReader.entries(from: source))
            }.value
            source = opened
            entries = listed
            isLoading = false
        } catch {
            // Backing out mid download cancels this; not an open failure, so don't flash the
            // "couldn't open archive" screen on the way out.
            guard !Task.isCancelled else { return }
            errorMessage = (error as? FilesClientError)?.userMessage ?? L10n.Archive.openArchiveFailed
            isLoading = false
        }
    }

    private static func temporaryDirectory(for item: FileItem) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveBrowser", isDirectory: true)
            .appendingPathComponent(item.id.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

#Preview("Loading") {
    ArchiveBrowserView(
        item: FileItem(name: "bundle.zip", path: "", dateModified: Date(), size: 0, kind: "zip"),
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        onDismiss: {}
    )
}
