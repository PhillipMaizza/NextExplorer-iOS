import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import SwiftUI

private enum Constants {
    static let iconSize: CGFloat = .size20
    static let toolbarHorizontalPadding: CGFloat = .space16
    static let toolbarVerticalPadding: CGFloat = .space12
    static let toolbarSpacing: CGFloat = .space16
    static let editorPadding: CGFloat = .space16
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
    let onDismiss: () -> Void

    @State private var draft = ""
    @State private var renderedMarkdownHTML = ""
    @State private var isEditing = false
    @AppStorage("renderHTMLPages") private var renderHTMLPages = false
    @AppStorage("renderMarkdownPages") private var renderMarkdownPages = false
    @Dependency(\.filesClient) private var filesClient

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
        VStack(spacing: 0) {
            toolbar
            Divider()
            editorBody
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .onAppear {
            draft = content ?? ""
            refreshRenderedMarkdown()
        }
        .onChange(of: content) { _, newValue in
            draft = newValue ?? ""
            refreshRenderedMarkdown()
        }
    }

    /// `MarkdownRenderer.html` re-parses the whole document — memoized here rather than
    /// called inline from `editorBody`, which would otherwise re-run it synchronously on the
    /// main thread on every unrelated SwiftUI re-render while in rendered mode.
    private func refreshRenderedMarkdown() {
        guard isMarkdown else { return }
        renderedMarkdownHTML = MarkdownRenderer.html(from: draft)
    }

    private var toolbar: some View {
        HStack(spacing: Constants.toolbarSpacing) {
            DSCloseButton(action: onDismiss)

            Text(fileName)
                .type(.body1(.semibold), style: .primary(for: .label))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            editToggleButton
        }
        .padding(.horizontal, Constants.toolbarHorizontalPadding)
        .padding(.vertical, Constants.toolbarVerticalPadding)
    }

    @ViewBuilder
    private var editToggleButton: some View {
        if isSaving {
            ProgressView()
        } else if content != nil {
            Button(action: toggleEditing) {
                (isEditing ? IconKit.checkmark : IconKit.squareAndPencil)
                    .resizable()
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
                    .foregroundStyle(Color.primaryDS)
            }
        }
    }

    private func toggleEditing() {
        if isEditing {
            onSave(draft)
            refreshRenderedMarkdown()
        }
        isEditing.toggle()
    }

    @ViewBuilder
    private var editorBody: some View {
        if let errorMessage {
            statusContent(icon: IconKit.exclamationmarkTriangle, message: errorMessage, tint: .negative)
        } else if isLoading {
            statusContent(icon: nil, message: nil, tint: .primaryDS)
        } else if isHTML, renderHTMLPages, !isEditing {
            // "Render HTML Pages" in Settings — editing always drops back to code (there's no
            // in-place editor for a rendered page), regardless of this setting.
            HTMLRenderedView(cacheKey: item.id, html: draft, resolveAsset: resolveServerAsset)
        } else if isMarkdown, renderMarkdownPages, !isEditing {
            // "Render Markdown Files" in Settings — same rendering pipeline as HTML, fed
            // compiled-to-HTML Markdown instead of the raw source.
            HTMLRenderedView(cacheKey: item.id, html: renderedMarkdownHTML, resolveAsset: resolveServerAsset)
        } else {
            // Real tree-sitter syntax highlighting (Runestone) — kept visible whether or not
            // `isEditing` is on, not just while actively editing, since highlighting helps
            // reading just as much as writing.
            CodeEditorView(kind: kind, text: $draft, isEditable: isEditing)
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
        onDismiss: {}
    )
}

#Preview("Reading") {
    TextFilePreviewView(
        item: FileItem(name: "README.md", path: "", dateModified: Date(), size: 0, kind: "md"),
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        fileName: "README.md",
        kind: "md",
        content: "# NEXTplorer\n\nA native iOS client for NextExplorer.",
        errorMessage: nil,
        isLoading: false,
        isSaving: false,
        onSave: { _ in },
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
        errorMessage: "Couldn't load this file. Check your connection and try again.",
        isLoading: false,
        isSaving: false,
        onSave: { _ in },
        onDismiss: {}
    )
}
