import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI
import Unrar
import ZIPFoundation

private enum Constants {
    static let toolbarSpacing: CGFloat = .space16
    static let toolbarHorizontalPadding: CGFloat = .space16
    static let toolbarVerticalPadding: CGFloat = .space12
    static let backIconSize: CGFloat = .iconSmall
    static let rowIconSize: CGFloat = .iconMedium
    static let statusSpacing: CGFloat = .space16
}

/// One entry inside a `.zip`/`.rar`, normalized across both underlying libraries' own
/// `Entry` types — `path` is the entry's full path within the archive (e.g. `"a/b/c.txt"`),
/// same shape whether it came from `ZIPFoundation` or `Unrar.swift`.
struct ArchiveEntry: Sendable {
    let path: String
    let isDirectory: Bool
    let size: UInt64
}

enum ArchiveReaderError: Error {
    case unsupportedFormat
    case entryNotFound
}

/// Keeps the archive open (`ZIPFoundation.Archive` holds a live file handle; `Unrar.Archive`
/// re-opens per call but this still avoids re-downloading) for the lifetime of
/// `ArchiveBrowserView`, so opening an entry for preview — including sibling asset lookups for
/// an in-archive HTML/Markdown render — never re-fetches the archive itself. `rarEntries` is a
/// cache, not part of the "source" concept — `Unrar.Archive.entries()` fully re-parses the
/// archive's header list on every call, so without this, previewing an HTML file with N
/// sibling assets inside a `.rar` would re-parse the whole archive N+1 times.
private final class ArchiveSource {
    let kind: Kind
    private var cachedRarEntries: [Unrar.Entry]?

    enum Kind {
        case zip(ZIPFoundation.Archive)
        case rar(Unrar.Archive)
    }

    init(_ kind: Kind) {
        self.kind = kind
    }

    fileprivate func rarEntries() throws -> [Unrar.Entry] {
        guard case let .rar(archive) = kind else { return [] }
        if let cachedRarEntries { return cachedRarEntries }
        let entries = try archive.entries()
        cachedRarEntries = entries
        return entries
    }
}

/// Reads a downloaded archive's contents entirely on-device — there's no server endpoint for
/// this (`POST /api/files/zip/extract` only fully unpacks to disk), so this is the only way
/// to show what's inside without materializing every archive a user taps.
enum ArchiveReader {
    fileprivate static func open(fileURL: URL, kind: String) throws -> ArchiveSource {
        switch kind.lowercased() {
        case "zip": return ArchiveSource(.zip(try ZIPFoundation.Archive(url: fileURL, accessMode: .read)))
        case "rar": return ArchiveSource(.rar(try Unrar.Archive(fileURL: fileURL)))
        default: throw ArchiveReaderError.unsupportedFormat
        }
    }

    fileprivate static func entries(from source: ArchiveSource) throws -> [ArchiveEntry] {
        switch source.kind {
        case let .zip(archive):
            return archive.map { entry in
                ArchiveEntry(path: entry.path, isDirectory: entry.type == .directory, size: entry.uncompressedSize)
            }
        case .rar:
            return try source.rarEntries().map { entry in
                ArchiveEntry(path: entry.fileName, isDirectory: entry.directory, size: entry.uncompressedSize)
            }
        }
    }

    /// Extracts a single entry, by its full in-archive path, to `destinationURL`. Both
    /// branches stream to disk rather than buffering the whole entry in memory — the rar
    /// branch via `Unrar.Archive`'s chunked `extract(_:handler:)`, matching what
    /// `ZIPFoundation.Archive.extract(_:to:)` already does internally — so opening a
    /// multi-gigabyte video from inside an archive doesn't hold the whole thing in RAM first.
    fileprivate static func extract(_ entryPath: String, from source: ArchiveSource, to destinationURL: URL) throws {
        switch source.kind {
        case let .zip(archive):
            guard let entry = archive[entryPath] else { throw ArchiveReaderError.entryNotFound }
            _ = try archive.extract(entry, to: destinationURL)
        case let .rar(archive):
            guard let entry = try source.rarEntries().first(where: { $0.fileName == entryPath }) else {
                throw ArchiveReaderError.entryNotFound
            }
            guard FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
                throw ArchiveReaderError.entryNotFound
            }
            let fileHandle = try FileHandle(forWritingTo: destinationURL)
            defer { try? fileHandle.close() }
            try archive.extract(entry) { chunk, _ in
                fileHandle.write(chunk)
            }
        }
    }
}

/// One row of the current folder level within `ArchiveBrowserView` — directories are
/// synthesized from entry path prefixes (most archives don't include explicit directory
/// entries for every intermediate folder), not just the ones the archive lists directly.
private struct ArchiveRow: Identifiable {
    let name: String
    let isDirectory: Bool
    let size: UInt64?

    var id: String { name }
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
    @State private var previewingItem: FileItem?
    @State private var previewFileURL: URL?
    @State private var toastMessage: DSToastMessage?
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
        ZStack {
            VStack(spacing: 0) {
                toolbar
                Divider()
                content
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())

            // An overlay, not a second `.fullScreenCover` — `ArchiveBrowserView` is itself
            // already presented via `BrowseContentView`'s `.fullScreenCover`, and stacking a
            // second `fullScreenCover` on top of the first is a real, reproducible SwiftUI
            // failure mode: the inner cover can render as a blank/black screen with no
            // interactive content, and no dismiss gesture reaches it either. Layering within
            // the same presentation avoids creating a second UIKit presentation controller.
            if let previewingItem, let previewFileURL {
                ArchiveEntryPreviewView(
                    item: previewingItem,
                    fileURL: previewFileURL,
                    serverURL: serverURL,
                    resolveAsset: { relativePath in await resolveAsset(relativePath, relativeTo: previewingItem.path) },
                    onDismiss: {
                        self.previewingItem = nil
                        self.previewFileURL = nil
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .dsToast($toastMessage)
        .animation(.default, value: previewingItem?.id)
        .task {
            await load()
        }
    }

    private var toolbar: some View {
        HStack(spacing: Constants.toolbarSpacing) {
            if currentPath.isEmpty {
                DSCloseButton(action: onDismiss, accessibilityLabel: L10n.Common.close)
            } else {
                Button {
                    currentPath.removeLast()
                } label: {
                    IconKit.back
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.primaryDS)
                        .frame(width: Constants.backIconSize, height: Constants.backIconSize)
                }
            }

            Text(title)
                .type(.body1(.semibold), style: .primary(for: .label))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(.horizontal, Constants.toolbarHorizontalPadding)
        .padding(.vertical, Constants.toolbarVerticalPadding)
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
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func rowContent(_ row: ArchiveRow) -> some View {
        HStack(spacing: Constants.toolbarSpacing) {
            if row.isDirectory {
                IconKit.folderFill
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.accent)
                    .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
            } else {
                FileTypeIcon(kind: (row.name as NSString).pathExtension)
                    .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
            }
            Text(row.name).type(.body2(.regular), style: .primary(for: .label))
            Spacer()
            if let size = row.size {
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
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleTap(_ row: ArchiveRow) {
        guard !row.isDirectory else {
            currentPath.append(row.name)
            return
        }
        let fullPath = currentPath.isEmpty ? row.name : currentPath.joined(separator: "/") + "/" + row.name
        let parent = (fullPath as NSString).deletingLastPathComponent
        let entryItem = FileItem(
            name: row.name,
            path: parent,
            dateModified: Date(timeIntervalSince1970: 0),
            size: Int64(row.size ?? 0),
            kind: (row.name as NSString).pathExtension
        )
        guard !entryItem.isUnsupportedForPreview else {
            toastMessage = DSToastMessage(icon: IconKit.warning, text: L10n.Archive.unsupportedFileType)
            return
        }
        guard let source else { return }
        do {
            let destination = Self.temporaryDirectory(for: item).appendingPathComponent(row.name)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ArchiveReader.extract(fullPath, from: source, to: destination)
            previewFileURL = destination
            previewingItem = entryItem
        } catch {
            toastMessage = DSToastMessage(icon: IconKit.warning, text: L10n.Archive.openFailed)
        }
    }

    /// Resolves and extracts a sibling asset referenced by an in-archive HTML/Markdown file
    /// (e.g. `style.css` next to `page.html`) from the same open archive — the archive
    /// equivalent of `TextFilePreviewView.resolveServerAsset`.
    private func resolveAsset(_ relativePath: String, relativeTo directory: String) async -> URL? {
        guard let source, let resolved = RelativeAssetPath.resolve(relativePath, relativeTo: directory) else { return nil }
        let entryPath = resolved.parent.isEmpty ? resolved.name : "\(resolved.parent)/\(resolved.name)"
        let destination = Self.temporaryDirectory(for: item).appendingPathComponent("assets").appendingPathComponent(entryPath)
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        return (try? ArchiveReader.extract(entryPath, from: source, to: destination)) != nil ? destination : nil
    }

    private func load() async {
        do {
            let fileURL = try await filesClient.downloadRawFile(serverURL, item)
            let opened = try ArchiveReader.open(fileURL: fileURL, kind: item.kind)
            source = opened
            entries = try ArchiveReader.entries(from: opened)
            isLoading = false
        } catch {
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

/// Preview for a file extracted from inside an archive — deliberately mirrors, rather than
/// reuses, `BrowseContentView.previewContent(for:)`'s branching: that one is wired to
/// `BrowseFeature`'s store-driven fetch/save actions, which don't apply here (no server path
/// to save back to, content already sits fully extracted on disk).
private struct ArchiveEntryPreviewView: View {
    let item: FileItem
    let fileURL: URL
    let serverURL: URL
    let resolveAsset: (String) async -> URL?
    let onDismiss: () -> Void

    var body: some View {
        if item.isPreviewableViaDownload {
            FilePreviewContainerView(fileURL: fileURL, errorMessage: nil, onDismiss: onDismiss)
        } else if item.isStreamableMedia {
            // `item.supportsThumbnail` is always `false` for archive entries (no server
            // metadata to know otherwise), so `StreamingPreviewView`'s poster never renders
            // here — `serverURL` is otherwise unused for a local file URL.
            StreamingPreviewView(item: item, url: fileURL, serverURL: serverURL, onDismiss: onDismiss)
        } else {
            ArchiveTextEntryPreviewView(item: item, fileURL: fileURL, resolveAsset: resolveAsset, onDismiss: onDismiss)
        }
    }
}

/// Read-only text/code viewer for an archive entry — no save action exists (there's nothing
/// to save back into: the archive isn't re-written), so unlike `TextFilePreviewView` this has
/// no edit toggle at all.
private struct ArchiveTextEntryPreviewView: View {
    let item: FileItem
    let fileURL: URL
    let resolveAsset: (String) async -> URL?
    let onDismiss: () -> Void

    @State private var content: String?
    @State private var renderedMarkdownHTML = ""
    @State private var loadErrorMessage: String?
    @AppStorage("renderHTMLPages") private var renderHTMLPages = false
    @AppStorage("renderMarkdownPages") private var renderMarkdownPages = false

    private var isHTML: Bool {
        let lowercaseKind = item.kind.lowercased()
        return lowercaseKind == "html" || lowercaseKind == "htm"
    }

    private var isMarkdown: Bool {
        let lowercaseKind = item.kind.lowercased()
        return lowercaseKind == "md" || lowercaseKind == "markdown"
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            body_
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .task {
            content = try? String(contentsOf: fileURL, encoding: .utf8)
            if let content, isMarkdown {
                // Memoized once here rather than called inline from `body_`, which would
                // otherwise re-parse the whole document synchronously on every unrelated
                // SwiftUI re-render while in rendered mode.
                renderedMarkdownHTML = MarkdownRenderer.html(from: content)
            }
            if content == nil { loadErrorMessage = L10n.Archive.openFailed }
        }
    }

    private var toolbar: some View {
        HStack(spacing: .space16) {
            DSCloseButton(action: onDismiss, accessibilityLabel: L10n.Common.close)
            Text(item.name)
                .type(.body1(.semibold), style: .primary(for: .label))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, .space16)
        .padding(.vertical, .space12)
    }

    @ViewBuilder
    private var body_: some View {
        if let loadErrorMessage {
            VStack(spacing: .space16) {
                IconKit.warning
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.negative)
                    .frame(width: .iconMedium, height: .iconMedium)
                Text(loadErrorMessage).type(.body1(.regular), style: .secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let content {
            if isHTML, renderHTMLPages {
                HTMLRenderedView(cacheKey: item.id, html: content, resolveAsset: resolveAsset)
            } else if isMarkdown, renderMarkdownPages {
                HTMLRenderedView(cacheKey: item.id, html: renderedMarkdownHTML, resolveAsset: resolveAsset)
            } else {
                CodeEditorView(kind: item.kind, text: .constant(content), isEditable: false)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview("Loading") {
    ArchiveBrowserView(
        item: FileItem(name: "bundle.zip", path: "", dateModified: Date(), size: 0, kind: "zip"),
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        onDismiss: {}
    )
}
