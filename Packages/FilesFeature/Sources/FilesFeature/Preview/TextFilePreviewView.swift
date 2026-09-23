import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

private enum Constants {
    static let statusSpacing: CGFloat = .space16
}

/// Full-screen viewer/editor for plain-text and code files — the only "edit docs" scope the
/// user confirmed. The real `/api/preview` endpoint only serves images/RAW/video/audio/PDF,
/// so these kinds never go through `FilesClient.previewFile`; content comes from
/// `GET /api/editor` as raw text and saves back via `PUT /api/editor` instead.
struct TextFilePreviewView: View {
    let item: FileItem
    let serverURL: URL
    let fileName: String
    let kind: String
    let content: String?
    let errorMessage: String?
    let isLoading: Bool
    let isSaving: Bool
    let onSave: (String) -> Void
    let onRetry: () -> Void
    let onDismiss: () -> Void

    /// The edit buffer, `nil` until the user first types. While `nil`, the editor reads `content`
    /// directly, so a freshly mounted `CodeEditorView` gets the full document on its very first
    /// `makeUIView` instead of an empty string that a lagged `draft` copy would swap in one render
    /// later. That empty then swap is what left Runestone's document half built and blank when the
    /// content arrived after the editor mounted (a slow "Everywhere" search hit this every time).
    @State private var draft: String?
    @State private var renderedMarkdownHTML = ""
    @State private var isEditing = false
    @State private var savedToast: DSToastMessage?
    @AppStorage(AppStorageKeys.renderHTMLPages) private var renderHTMLPages = false
    @AppStorage(AppStorageKeys.renderMarkdownPages) private var renderMarkdownPages = false
    @Environment(\.openURL) private var openURL
    @Dependency(\.filesClient) private var filesClient

    /// The text currently shown/edited: the edit buffer once the user has typed, otherwise the
    /// loaded `content` verbatim.
    private var currentText: String {
        draft ?? content ?? ""
    }

    /// Editor binding: reads `currentText` (so the first render already has the full document),
    /// writes land in `draft`.
    private var editorText: Binding<String> {
        Binding(get: { currentText }, set: { draft = $0 })
    }

    private var isHTML: Bool {
        let lowercaseKind = kind.lowercased()
        return lowercaseKind == "html" || lowercaseKind == "htm"
    }

    private var isMarkdown: Bool {
        let lowercaseKind = kind.lowercased()
        return lowercaseKind == "md" || lowercaseKind == "markdown"
    }

    /// Downloads a same-folder asset (`downloadRawFile` has no extension restriction, unlike
    /// `previewFile`'s `GET /api/preview`) — shared by both the HTML and Markdown render
    /// paths, since both ultimately go through the same `HTMLRenderedView`.
    private func resolveServerAsset(relativePath: String) async -> URL? {
        guard let resolved = RelativeAssetPath.resolve(relativePath, relativeTo: item.path) else { return nil }
        let sibling = FileItem(name: resolved.name, path: resolved.parent, dateModified: Date(timeIntervalSince1970: 0), size: 0, kind: (resolved.name as NSString).pathExtension)
        return try? await filesClient.downloadRawFile(serverURL, sibling)
    }

    var body: some View {
        NavigationStack {
            editorBody
                .background(Color.backgroundPrimary.ignoresSafeArea())
                .navigationTitle(fileName)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackgroundHidden()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { editToggleButton }
                    if isHTML {
                        ToolbarItem(placement: .topBarTrailing) { openInBrowserButton }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button { onDismiss() } label: { IconKit.close.foregroundStyle(Color.primaryDS) }
                            .accessibilityLabel(L10n.Common.close)
                    }
                }
        }
        .dsToast($savedToast)
        // A new document (first load, or the reload after a save) discards any stale edit buffer so
        // the editor follows the authoritative `content` again.
        .onChange(of: content) { _, _ in draft = nil }
        // `MarkdownRenderer.html` parses the whole document; run it off the main thread so a
        // large Markdown file doesn't freeze the UI on open. `.task(id:)` cancels a superseded
        // render, so a fast content change can't land a stale HTML string.
        .task(id: content) {
            guard isMarkdown else {
                renderedMarkdownHTML = ""
                return
            }
            let source = content ?? ""
            let html = await Task.detached(priority: .userInitiated) {
                MarkdownRenderer.html(from: source)
            }.value
            if !Task.isCancelled {
                renderedMarkdownHTML = html
            }
        }
        .onChange(of: isSaving) { wasSaving, nowSaving in
            if wasSaving, !nowSaving, errorMessage == nil {
                savedToast = .success(L10n.TextPreview.saved)
                isEditing = false
            }
        }
    }

    /// Leading nav-bar item: toggles the Runestone editor between read-only and editable; the
    /// checkmark state saves on tap. Hidden until there's content to edit.
    @ViewBuilder
    private var editToggleButton: some View {
        if isSaving {
            DSSpinner()
        } else if content != nil {
            Button(action: toggleEditing) {
                (isEditing ? IconKit.checkmark : IconKit.rename)
                    .foregroundStyle(Color.primaryDS)
            }
            .accessibilityLabel(isEditing ? L10n.Common.save : L10n.Common.edit)
        }
    }

    /// Trailing nav-bar item for `.html` files: hands the file's `/api/raw` URL to Safari.
    /// The server has no rendered-HTML endpoint, so Safari shows the source (and a login page
    /// first if the server requires auth).
    @ViewBuilder
    private var openInBrowserButton: some View {
        if let url = FilesClient.rawFileURL(serverURL: serverURL, item: item) {
            Button {
                openURL(url)
            } label: {
                IconKit.web.foregroundStyle(Color.primaryDS)
            }
            .accessibilityLabel(L10n.Browse.actionOpenInBrowser)
        }
    }

    private func toggleEditing() {
        // Saving updates `content` upstream, which re-fires the markdown render task above.
        if isEditing {
            onSave(currentText)
        }
        isEditing.toggle()
    }

    @ViewBuilder
    private var editorBody: some View {
        if let errorMessage {
            errorContent(errorMessage)
        } else if isLoading {
            DSSpinner()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isHTML, renderHTMLPages, !isEditing {
            // "Render HTML Pages" in Settings — editing always drops back to code (there's no
            // in-place editor for a rendered page), regardless of this setting.
            HTMLRenderedView(cacheKey: item.id, html: currentText, resolveAsset: resolveServerAsset)
        } else if isMarkdown, renderMarkdownPages, !isEditing {
            // "Render Markdown Files" in Settings — same rendering pipeline as HTML, fed
            // compiled-to-HTML Markdown instead of the raw source.
            HTMLRenderedView(cacheKey: item.id, html: renderedMarkdownHTML, resolveAsset: resolveServerAsset)
        } else {
            // Real tree-sitter syntax highlighting (Runestone) — kept visible whether or not
            // `isEditing` is on, not just while actively editing, since highlighting helps
            // reading just as much as writing.
            CodeEditorView(kind: kind, text: editorText, isEditable: isEditing)
        }
    }

    /// Load failure: the warning + message plus a retry that re-fires the `/api/editor` fetch,
    /// so a transient network error isn't a dead end that forces closing the preview.
    private func errorContent(_ message: String) -> some View {
        VStack(spacing: Constants.statusSpacing) {
            IconKit.warning
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.negative)
                .frame(width: .iconMedium, height: .iconMedium)
            Text(message)
                .type(.body1(.regular), style: .secondary)
                .multilineTextAlignment(.center)
            RetryLinkButton(action: onRetry)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, .space16)
    }
}

#Preview("Loading") {
    TextFilePreviewView(
        item: FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 0, kind: "txt"),
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        fileName: "notes.txt",
        kind: "txt",
        content: nil,
        errorMessage: nil,
        isLoading: true,
        isSaving: false,
        onSave: { _ in },
        onRetry: {},
        onDismiss: {}
    )
}

#Preview("Reading") {
    TextFilePreviewView(
        item: FileItem(name: "README.md", path: "", dateModified: Date(), size: 0, kind: "md"),
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        fileName: "README.md",
        kind: "md",
        content: "# NextExplorer\n\nA native iOS client for NextExplorer.",
        errorMessage: nil,
        isLoading: false,
        isSaving: false,
        onSave: { _ in },
        onRetry: {},
        onDismiss: {}
    )
}

#Preview("Saving") {
    TextFilePreviewView(
        item: FileItem(name: "config.json", path: "", dateModified: Date(), size: 0, kind: "json"),
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        fileName: "config.json",
        kind: "json",
        content: "{\n  \"key\": \"value\"\n}",
        errorMessage: nil,
        isLoading: false,
        isSaving: true,
        onSave: { _ in },
        onRetry: {},
        onDismiss: {}
    )
}

#Preview("Error") {
    TextFilePreviewView(
        item: FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 0, kind: "txt"),
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        fileName: "notes.txt",
        kind: "txt",
        content: nil,
        errorMessage: L10n.TextPreview.loadFailed,
        isLoading: false,
        isSaving: false,
        onSave: { _ in },
        onRetry: {},
        onDismiss: {}
    )
}
