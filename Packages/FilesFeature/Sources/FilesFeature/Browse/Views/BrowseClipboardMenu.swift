import ComposableArchitecture
import DesignSystem
import Localization
import SwiftUI

/// The toolbar's clipboard section: paste what was copied or cut, or forget it.
struct BrowseClipboardMenu: View {
    let store: StoreOf<BrowseFeature>
    let shouldKeepClipboard: Bool

    var body: some View {
        if store.clipboard != nil, !store.directoryPath.isEmpty {
            Section {
                Button {
                    store.send(.pasteTapped(keepItemsAfterCopy: shouldKeepClipboard), animation: DSMotion.listDiff)
                } label: {
                    Label { Text(BrowsePasteMenu.actionTitle(store)) } icon: { IconKit.paste }
                }
                .disabled(!BrowsePasteMenu.canPaste(store))
                Button {
                    store.send(.clipboardCleared, animation: DSMotion.listDiff)
                } label: {
                    Label { Text(L10n.Browse.actionClearClipboard) } icon: { IconKit.close }
                }
            }
        }
    }
}

#Preview {
    Menu(L10n.Browse.actionClearClipboard) {
        BrowseClipboardMenu(
            store: Store(initialState: .preview(items: browsePreviewItems)) { BrowseFeature() },
            shouldKeepClipboard: false
        )
    }
}
