import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// Full screen viewer/editor for plain text and code files: the only "edit docs" scope the
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
    /// A file the user just created opens ready to type, once; any other file opens to read.
    var shouldStartEditing = false

    /// The edit buffer, `nil` until the user first types. While `nil`, the editor reads `content`
    /// directly, so a freshly mounted `CodeEditorView` gets the full document on its very first
    /// `makeUIView` instead of an empty string that a lagged `draft` copy would swap in one render
    /// later. That empty then swap is what left Runestone's document half built and blank when the
    /// content arrived after the editor mounted (a slow "Everywhere" search hit this every time).
    @State private var draft: String?
    @State private var isEditing = false
    @State private var savedToast: DSToastMessage?
    /// Closing with edits not yet saved: asking first, then (Save) closing once the save lands.
    @State private var closeFlow = CloseFlow.idle

    private enum CloseFlow: Equatable {
        case idle
        case confirming
        case savingThenClosing
    }

    private var isConfirmingClose: Binding<Bool> {
        Binding(get: { closeFlow == .confirming }, set: { isShown in
            if !isShown, closeFlow == .confirming {
                closeFlow = .idle
            }
        })
    }

    @Environment(\.openURL) private var openURL

    /// The text currently shown/edited: the edit buffer once the user has typed, otherwise the
    /// loaded `content` verbatim.
    private var currentText: String {
        draft ?? content ?? ""
    }

    private var hasUnsavedChanges: Bool {
        isEditing && draft != nil && draft != content
    }

    /// Close asks first when there are edits, like any document editor, instead of dropping them.
    private func requestClose() {
        if hasUnsavedChanges {
            closeFlow = .confirming
        } else {
            onDismiss()
        }
    }

    /// Editor binding: reads `currentText` (so the first render already has the full document),
    /// writes land in `draft`.
    private var editorText: Binding<String> {
        Binding(get: { currentText }, set: { draft = $0 })
    }

    private var isHTML: Bool {
        FileItem.isHTML(kind: kind)
    }

    var body: some View {
        chrome
            .dsToast($savedToast)
            .dsAlert(isPresented: isConfirmingClose) {
                DSAlertSheet(
                    icon: IconKit.rename,
                    title: L10n.TextPreview.unsavedTitle(fileName),
                    message: L10n.TextPreview.unsavedMessage,
                    confirmTitle: L10n.Common.save,
                    dismissTitle: L10n.Common.cancel,
                    neutralTitle: L10n.TextPreview.dontSave,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: {
                        closeFlow = .savingThenClosing
                        onSave(currentText)
                    },
                    onNeutral: {
                        closeFlow = .idle
                        onDismiss()
                    },
                    onDismiss: { closeFlow = .idle }
                )
            }
            // A new document (first load, or the reload after a save) discards any stale edit buffer so
            // the editor follows the authoritative `content` again.
            .onChange(of: content) { _, _ in draft = nil }
            .onAppear {
                if shouldStartEditing {
                    isEditing = true
                }
            }
            .onChange(of: isSaving) { wasSaving, nowSaving in
                guard wasSaving, !nowSaving else { return }
                let shouldClose = closeFlow == .savingThenClosing
                closeFlow = .idle
                if errorMessage == nil {
                    savedToast = .success(L10n.TextPreview.saved)
                    isEditing = false
                    if shouldClose {
                        onDismiss()
                    }
                }
            }
    }

    private var chrome: some View {
        #if os(macOS)
            // A Mac sheet has no navigation toolbar: Close, Edit and Save sit in the preview bar,
            // and ⌘S saves while editing, like any Mac editor.
            editorBody
                .background(Color.backgroundPrimary.ignoresSafeArea())
                .macPreviewBar(title: fileName, onClose: requestClose) {
                    EmptyView()
                } trailing: {
                    if isHTML {
                        openInBrowserButton
                    }
                    editToggleButton
                        .keyboardShortcut(isEditing ? KeyboardShortcut("s") : nil)
                }
        #else
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
                            Button { requestClose() } label: { IconKit.close.foregroundStyle(Color.primaryDS) }
                                .accessibilityLabel(L10n.Common.close)
                        }
                    }
            }
        #endif
    }

    /// Leading nav bar item: toggles the Runestone editor between read only and editable; the
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
            .accessibilityLabelWithTooltip(isEditing ? L10n.Common.save : L10n.Common.edit)
        }
    }

    /// Trailing nav bar item for `.html` files: hands the file's `/api/raw` URL to Safari.
    /// The server has no rendered HTML endpoint, so Safari shows the source (and a login page
    /// first if the server requires auth).
    @ViewBuilder
    private var openInBrowserButton: some View {
        if let url = FilesClient.rawFileURL(serverURL: serverURL, item: item) {
            Button {
                openURL(url)
            } label: {
                IconKit.web.foregroundStyle(Color.primaryDS)
            }
            .accessibilityLabelWithTooltip(L10n.Browse.actionOpenInBrowser)
        }
    }

    private func toggleEditing() {
        // Saving updates `content` upstream, which refires the markdown render task above.
        if isEditing {
            onSave(currentText)
        }
        isEditing.toggle()
    }

    @ViewBuilder
    private var editorBody: some View {
        if let errorMessage {
            PreviewErrorView(message: errorMessage, onRetry: onRetry)
        } else if isLoading {
            DSSpinner()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TextDocumentBody(
                item: item,
                serverURL: serverURL,
                kind: kind,
                content: content,
                text: editorText,
                isEditing: isEditing,
                onEscape: requestClose
            )
        }
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
