import AppStorageKeys
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let statusSpacing: CGFloat = .space16
    /// Chrome crossfade when tapping a full-screen archive image, matching `ImageGalleryView`.
    static let chromeFadeDuration: Double = 0.22
    /// A text/markdown entry is only ever read this far in for preview — an archive can hold a
    /// multi-gigabyte "text" file, and `String(contentsOf:)` would pull all of it into memory.
    static let maxTextPreviewBytes = 5 * 1024 * 1024
}

/// Preview for a file extracted from inside an archive — deliberately mirrors, rather than
/// reuses, `BrowsePreviewRouter`'s branching: that one is wired to `BrowseFeature`'s
/// store-driven fetch/save actions, which don't apply here (no server path to save back to,
/// content already sits fully extracted on disk).
struct ArchiveEntryPreviewView: View {
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
        } else if item.isBrowsableArchive {
            // A nested .zip/.rar: browse the already-extracted local file in place, rather than
            // falling through to the text viewer and showing its raw bytes.
            ArchiveBrowserView(item: item, serverURL: serverURL, localFileURL: fileURL, onDismiss: onDismiss)
        } else if item.isImage || item.isRawImage, !item.isSVG {
            ArchiveImagePreviewView(
                fileName: item.name,
                fileURL: fileURL,
                isGIF: item.kind.lowercased() == "gif",
                onDismiss: onDismiss
            )
        } else if item.isPreviewableViaDownload {
            FilePreviewContainerView(fileURL: fileURL, errorMessage: nil, onDismiss: onDismiss)
        } else if item.isStreamableMedia {
            // Local extracted file, so no auth cookie needed either way. `item.supportsThumbnail`
            // is always `false` for archive entries, so `StreamingPreviewView`'s poster never
            // renders. Non native containers/codecs play through libvlc via `VLCPlayerView`.
            if item.isNativelyPlayable {
                StreamingPreviewView(item: item, url: fileURL, serverURL: serverURL, onDismiss: onDismiss)
            } else {
                VLCPlayerView(item: item, url: fileURL, serverURL: serverURL, onDismiss: onDismiss)
            }
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
                    DSSpinner()
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
            DSSpinner().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
