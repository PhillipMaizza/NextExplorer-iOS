import AppStorageKeys
import ComposableArchitecture
import CoreModels
import FilesClient
import SwiftUI

/// A text file's content: rendered as a page for HTML and Markdown when Settings asks for it and
/// the file is not being edited, otherwise syntax highlighted code. Shared by the editor and the
/// gallery's read only text page.
struct TextDocumentBody: View {
    let item: FileItem
    let serverURL: URL
    let kind: String
    /// The text as loaded; the Markdown render follows it.
    let content: String?
    /// What the code view shows and, while editing, writes.
    @Binding var text: String
    var isEditing = false
    /// Room for bars floating over the page: the text starts below them and scrolls under.
    var contentInsets = EdgeInsets()
    /// A tap while reading, for the gallery to show and hide its bars.
    var onTap: (() -> Void)?
    var onEscape: (() -> Void)?

    @State private var renderedMarkdownHTML = ""
    @AppStorage(AppStorageKeys.renderHTMLPages) private var shouldRenderHTMLPages = false
    @AppStorage(AppStorageKeys.renderMarkdownPages) private var shouldRenderMarkdownPages = false
    @Dependency(\.filesClient) private var filesClient

    private var isHTML: Bool {
        let lowercaseKind = kind.lowercased()
        return lowercaseKind == "html" || lowercaseKind == "htm"
    }

    private var isMarkdown: Bool {
        let lowercaseKind = kind.lowercased()
        return lowercaseKind == "md" || lowercaseKind == "markdown"
    }

    var body: some View {
        document
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
    }

    @ViewBuilder
    private var document: some View {
        if isHTML, shouldRenderHTMLPages, !isEditing {
            // Editing always drops back to code: there's no in place editor for a rendered page.
            HTMLRenderedView(cacheKey: item.id, html: text, resolveAsset: resolveServerAsset)
                .padding(.top, contentInsets.top)
                .padding(.bottom, contentInsets.bottom)
        } else if isMarkdown, shouldRenderMarkdownPages, !isEditing {
            HTMLRenderedView(cacheKey: item.id, html: renderedMarkdownHTML, resolveAsset: resolveServerAsset)
                .padding(.top, contentInsets.top)
                .padding(.bottom, contentInsets.bottom)
        } else {
            // Tree sitter highlighting (Runestone) whether or not editing: it helps reading as much
            // as writing.
            #if os(macOS)
                CodeEditorView(kind: kind, text: $text, isEditable: isEditing, onEscape: onEscape)
            #else
                CodeEditorView(
                    kind: kind,
                    text: $text,
                    isEditable: isEditing,
                    contentInsets: UIEdgeInsets(
                        top: contentInsets.top,
                        left: 0,
                        bottom: contentInsets.bottom,
                        right: 0
                    ),
                    onTap: onTap
                )
            #endif
        }
    }

    /// Downloads a same folder asset (`downloadRawFile` has no extension restriction, unlike
    /// `previewFile`'s `GET /api/preview`) for both the HTML and the Markdown page.
    private func resolveServerAsset(relativePath: String) async -> URL? {
        guard let resolved = RelativeAssetPath.resolve(relativePath, relativeTo: item.path) else { return nil }
        let sibling = FileItem(
            name: resolved.name,
            path: resolved.parent,
            dateModified: Date(timeIntervalSince1970: 0),
            size: 0,
            kind: (resolved.name as NSString).pathExtension
        )
        return try? await filesClient.downloadRawFile(serverURL, sibling)
    }
}

#Preview("Code") {
    TextDocumentBody(
        item: FileItem(name: "config.json", path: "", dateModified: .distantPast, size: 24, kind: "json"),
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        kind: "json",
        content: "{\n  \"key\": \"value\"\n}",
        text: .constant("{\n  \"key\": \"value\"\n}")
    )
}

#Preview("Editing") {
    TextDocumentBody(
        item: FileItem(name: "notes.txt", path: "", dateModified: .distantPast, size: 5, kind: "txt"),
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        kind: "txt",
        content: "Hello",
        text: .constant("Hello, edited"),
        isEditing: true
    )
}

#Preview("Empty") {
    TextDocumentBody(
        item: FileItem(name: "empty.md", path: "", dateModified: .distantPast, size: 0, kind: "md"),
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        kind: "md",
        content: "",
        text: .constant("")
    )
}
