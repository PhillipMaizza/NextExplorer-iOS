#if os(macOS)
    import DesignSystem
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
                layout: .stacked,
                onCancel: onCancel,
                onConfirm: { onGo(path) }
            ) {
                MacTextField(L10n.Menu.goToFolderTitle, text: $path, prompt: L10n.Menu.goToFolderPlaceholder)
                    .monospaced()
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .onSubmit { onGo(path) }
            }
            .task { isFocused = true }
        }
    }

    #Preview {
        MacGoToFolderSheet(onGo: { _ in }, onCancel: {})
    }
#endif
