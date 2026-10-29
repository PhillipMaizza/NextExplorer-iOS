#if os(macOS)
    import Localization
    import SwiftUI

    /// Go ▸ Go to Folder… (⇧⌘G): type a server path, like Finder's dialog, and Browse opens it.
    struct MacGoToFolderSheet: View {
        let onGo: (String) -> Void
        let onCancel: () -> Void
        @State private var path = ""
        @FocusState private var isFocused: Bool

        var body: some View {
            MacFormSheet(
                title: L10n.Menu.goToFolderTitle,
                confirmTitle: L10n.Menu.go,
                isConfirmEnabled: !path.trimmingCharacters(in: .whitespaces).isEmpty,
                onCancel: onCancel,
                onConfirm: { onGo(path) }
            ) {
                TextField(L10n.Menu.goToFolderTitle, text: $path, prompt: Text(verbatim: "Documents/Reports"))
                    .labelsHidden()
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .onSubmit { onGo(path) }
            }
            .task { isFocused = true }
        }
    }
#endif
