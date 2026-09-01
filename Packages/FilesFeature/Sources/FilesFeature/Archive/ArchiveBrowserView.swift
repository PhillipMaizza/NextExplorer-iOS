import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI
import Unrar
import ZIPFoundation

private enum Constants {
    static let rowSpacing: CGFloat = .space16
    static let backIconSize: CGFloat = .iconSmall
    static let rowIconSize: CGFloat = .iconMedium
    static let statusSpacing: CGFloat = .space16
    /// Chrome crossfade when tapping a full-screen archive image, matching `ImageGalleryView`.
    static let chromeFadeDuration: Double = 0.22
    /// A text/markdown entry is only ever read this far in for preview — an archive can hold a
    /// multi-gigabyte "text" file, and `String(contentsOf:)` would pull all of it into memory.
    static let maxTextPreviewBytes = 5 * 1024 * 1024
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
    case entryTooLarge
}

/// Keeps the archive open (`ZIPFoundation.Archive` holds a live file handle; `Unrar.Archive`
/// re-opens per call but this still avoids re-downloading) for the lifetime of
/// `ArchiveBrowserView`, so opening an entry for preview — including sibling asset lookups for
/// an in-archive HTML/Markdown render — never re-fetches the archive itself. `rarEntries` is a
/// cache, not part of the "source" concept — `Unrar.Archive.entries()` fully re-parses the
/// archive's header list on every call, so without this, previewing an HTML file with N
/// sibling assets inside a `.rar` would re-parse the whole archive N+1 times.
/// `@unchecked Sendable`: `ZIPFoundation.Archive` / `Unrar.Archive` aren't thread-safe and
/// `cachedRarEntries` is mutable, so every access to the underlying handles goes through
/// `lock` — `entries()`, `extract(_:to:)` and the `rarEntries()` cache are all serialized by
/// the type itself rather than by a caller-side gating convention.
private final class ArchiveSource: @unchecked Sendable {
    let kind: Kind
    private let lock = NSLock()
    private var cachedRarEntries: [Unrar.Entry]?

    enum Kind {
        case zip(ZIPFoundation.Archive)
        case rar(Unrar.Archive)
    }

    init(_ kind: Kind) {
        self.kind = kind
    }

    func entries() throws -> [ArchiveEntry] {
        lock.lock()
        defer { lock.unlock() }
        switch kind {
        case let .zip(archive):
            return archive.map { entry in
                ArchiveEntry(path: entry.path, isDirectory: entry.type == .directory, size: entry.uncompressedSize)
            }
        case .rar:
            return try rarEntries().map { entry in
                ArchiveEntry(path: entry.fileName, isDirectory: entry.directory, size: entry.uncompressedSize)
            }
        }
    }

    /// Extracts a single entry, by its full in-archive path, to `destinationURL`. Both branches
    /// stream to disk rather than buffering the whole entry in memory, and both enforce a hard
    /// size ceiling (`ArchiveReader.guardExtraction` on the declared size, plus a running byte
    /// count on the actual stream) so a crafted archive whose header understates the inflated
    /// size still can't fill the device.
    func extract(_ entryPath: String, to destinationURL: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        switch kind {
        case let .zip(archive):
            guard let entry = archive[entryPath] else { throw ArchiveReaderError.entryNotFound }
            try ArchiveReader.guardExtraction(uncompressedSize: entry.uncompressedSize, destination: destinationURL)
            guard FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
                throw ArchiveReaderError.entryNotFound
            }
            let fileHandle = try FileHandle(forWritingTo: destinationURL)
            defer { try? fileHandle.close() }
            var written: UInt64 = 0
            _ = try archive.extract(entry, bufferSize: 1024 * 1024, skipCRC32: true) { chunk in
                written += UInt64(chunk.count)
                guard written <= ArchiveReader.maxEntrySize else { throw ArchiveReaderError.entryTooLarge }
                fileHandle.write(chunk)
            }
        case let .rar(archive):
            guard let entry = try rarEntries().first(where: { $0.fileName == entryPath }) else {
                throw ArchiveReaderError.entryNotFound
            }
            try ArchiveReader.guardExtraction(uncompressedSize: entry.uncompressedSize, destination: destinationURL)
            guard FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
                throw ArchiveReaderError.entryNotFound
            }
            let fileHandle = try FileHandle(forWritingTo: destinationURL)
            defer { try? fileHandle.close() }
            var written: UInt64 = 0
            var overflowed = false
            // `Unrar`'s handler can't throw, so once the running count passes the ceiling we stop
            // writing and report afterward — the decoder keeps running but nothing more hits disk.
            try archive.extract(entry) { chunk, _ in
                guard !overflowed else { return }
                written += UInt64(chunk.count)
                if written > ArchiveReader.maxEntrySize {
                    overflowed = true
                    return
                }
                fileHandle.write(chunk)
            }
            if overflowed { throw ArchiveReaderError.entryTooLarge }
        }
    }

    private func rarEntries() throws -> [Unrar.Entry] {
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
    /// Hard ceiling on a single extracted entry. A crafted archive (a "zip bomb") can declare a
    /// tiny compressed size yet inflate to hundreds of gigabytes; without a cap the streaming
    /// writer would fill the device before the write ever failed.
    static let maxEntrySize: UInt64 = 2 * 1024 * 1024 * 1024

    fileprivate static func open(fileURL: URL, kind: String) throws -> ArchiveSource {
        switch kind.lowercased() {
        case "zip": return ArchiveSource(.zip(try ZIPFoundation.Archive(url: fileURL, accessMode: .read)))
        case "rar": return ArchiveSource(.rar(try Unrar.Archive(fileURL: fileURL)))
        default: throw ArchiveReaderError.unsupportedFormat
        }
    }

    fileprivate static func entries(from source: ArchiveSource) throws -> [ArchiveEntry] {
        try source.entries()
    }

    fileprivate static func extract(_ entryPath: String, from source: ArchiveSource, to destinationURL: URL) throws {
        try source.extract(entryPath, to: destinationURL)
    }

    /// Rejects an extraction before it starts when the declared size exceeds the ceiling or the
    /// volume's available space, so an honest but huge entry never begins filling the disk.
    static func guardExtraction(uncompressedSize: UInt64, destination: URL) throws {
        guard uncompressedSize <= maxEntrySize else { throw ArchiveReaderError.entryTooLarge }
        if let available = availableCapacity(at: destination.deletingLastPathComponent()),
           uncompressedSize > available {
            throw ArchiveReaderError.entryTooLarge
        }
    }

    private static func availableCapacity(at url: URL) -> UInt64? {
        guard let capacity = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage else { return nil }
        return capacity >= 0 ? UInt64(capacity) : nil
    }
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
                ProgressView().controlSize(.small)
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
        if item.isUnsupportedForPreview {
            // Same Files-app style screen as the browse tab, minus the server actions — only
            // system-sharing the already-extracted file applies to an archive entry.
            UnsupportedFilePreviewView(item: item, systemShare: .local(fileURL), onDismiss: onDismiss)
        } else if (item.isImage || item.isRawImage) && !item.isSVG {
            ArchiveImagePreviewView(
                fileName: item.name,
                fileURL: fileURL,
                isGIF: item.kind.lowercased() == "gif",
                onDismiss: onDismiss
            )
        } else if item.isPreviewableViaDownload {
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

/// Full-screen image viewer for an archive entry — mirrors `ImageGalleryView`'s single-page
/// behavior (`ZoomableScrollView`, full-bleed, tap toggles the chrome) but reads straight
/// from the already-extracted local file rather than the server.
private struct ArchiveImagePreviewView: View {
    let fileName: String
    let fileURL: URL
    let isGIF: Bool
    let onDismiss: () -> Void

    @State private var areControlsHidden = false

    var body: some View {
        NavigationStack {
            imageContent
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: Constants.chromeFadeDuration)) {
                        areControlsHidden.toggle()
                    }
                }
                .navigationTitle(fileName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { onDismiss() } label: { IconKit.close.foregroundStyle(Color.primaryDS) }
                            .accessibilityLabel(L10n.Common.close)
                    }
                }
                .toolbar(areControlsHidden ? .hidden : .visible, for: .navigationBar)
                .statusBarHidden(areControlsHidden)
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if isGIF {
            ZoomableScrollView { AnimatedImageView(fileURL: fileURL) }
        } else {
            AsyncImage(url: fileURL) { phase in
                switch phase {
                case let .success(image):
                    ZoomableScrollView { image.resizable().scaledToFit() }
                case .failure:
                    VStack(spacing: Constants.statusSpacing) {
                        IconKit.warning
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(Color.negative)
                            .frame(width: .iconMedium, height: .iconMedium)
                        Text(L10n.Gallery.loadFailed).type(.body1(.regular), style: .secondary)
                    }
                default:
                    ProgressView()
                }
            }
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
    @AppStorage(AppStorageKeys.renderHTMLPages) private var renderHTMLPages = false
    @AppStorage(AppStorageKeys.renderMarkdownPages) private var renderMarkdownPages = false

    private var isHTML: Bool {
        let lowercaseKind = item.kind.lowercased()
        return lowercaseKind == "html" || lowercaseKind == "htm"
    }

    private var isMarkdown: Bool {
        let lowercaseKind = item.kind.lowercased()
        return lowercaseKind == "md" || lowercaseKind == "markdown"
    }

    var body: some View {
        NavigationStack {
            body_
                .backgroundGradient()
                .navigationTitle(item.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { onDismiss() } label: { IconKit.close.foregroundStyle(Color.primaryDS) }
                            .accessibilityLabel(L10n.Common.close)
                    }
                }
        }
        .task {
            // Read + (for Markdown) render off the main actor — a multi-megabyte entry would
            // otherwise block the UI while it decodes and parses. Memoized once here rather
            // than inline from `body_`, which would re-parse on every unrelated re-render.
            let shouldRenderMarkdown = isMarkdown
            let loaded: (text: String, markdownHTML: String)? = await Task.detached(priority: .userInitiated) {
                guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
                defer { try? handle.close() }
                let data = (try? handle.read(upToCount: Constants.maxTextPreviewBytes)) ?? Data()
                // A prefix read can slice a multi-byte character; `String(decoding:as:)`
                // substitutes U+FFFD rather than failing the whole preview.
                let text = String(decoding: data, as: UTF8.self)
                return (text, shouldRenderMarkdown ? MarkdownRenderer.html(from: text) : "")
            }.value
            guard let loaded else {
                loadErrorMessage = L10n.Archive.openFailed
                return
            }
            content = loaded.text
            renderedMarkdownHTML = loaded.markdownHTML
        }
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
