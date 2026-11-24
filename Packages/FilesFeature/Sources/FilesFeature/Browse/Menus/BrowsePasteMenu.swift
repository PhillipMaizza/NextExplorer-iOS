import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// The Paste Here and Clear Clipboard pair for the empty space of a folder and the Mac table menu.
/// Present only while something is staged, so an empty menu never opens.
struct BrowsePasteMenu: View {
    let store: StoreOf<BrowseFeature>
    let shouldKeepClipboard: Bool

    var body: some View {
        if store.clipboard != nil, !store.directoryPath.isEmpty {
            Button {
                store.send(.pasteTapped(keepItemsAfterCopy: shouldKeepClipboard), animation: DSMotion.listDiff)
            } label: {
                Label { Text(L10n.Browse.actionPasteHere) } icon: { IconKit.paste }
            }
            .disabled(!Self.canPaste(store))
            #if os(macOS)
                .keyboardShortcut(BrowseShortcut.paste)
            #endif
            Button {
                store.send(.clipboardCleared, animation: DSMotion.listDiff)
            } label: {
                Label { Text(L10n.Browse.actionClearClipboard) } icon: { IconKit.close }
            }
        }
    }

    /// Whether the current folder is a legitimate paste target for the staged clipboard.
    static func canPaste(_ store: StoreOf<BrowseFeature>) -> Bool {
        store.clipboard?.canPaste(into: store.directoryPath, canWrite: store.access?.canWrite ?? false) ?? false
    }

    /// "Paste" for a single staged item, "Paste N items" past that.
    static func actionTitle(_ store: StoreOf<BrowseFeature>) -> String {
        let count = store.clipboard?.items.count ?? 0
        return count <= 1 ? L10n.Browse.actionPaste : L10n.Browse.actionPasteCount(count)
    }
}

/// Invisible long press target filling the space past the last row: a plain `.contextMenu` on
/// the whole list or scroll container lifts a snapshot of the entire list on long press, which
/// reads as the list jumping. Scoping it to this transparent trailing area keeps the list still.
struct BrowsePasteTarget: View {
    let store: StoreOf<BrowseFeature>
    let shouldKeepClipboard: Bool
    var isListRow = false

    var body: some View {
        if store.clipboard != nil, !store.directoryPath.isEmpty {
            if isListRow {
                target
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                target
            }
        }
    }

    private var target: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: Constants.minHeight)
            .contentShape(Rectangle())
            .contextMenu { BrowsePasteMenu(store: store, shouldKeepClipboard: shouldKeepClipboard) }
    }

    private enum Constants {
        static let minHeight: CGFloat = 260
    }
}
