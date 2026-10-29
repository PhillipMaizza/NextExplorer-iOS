#if os(macOS)
    import AppFeature
    import AppKit
    import ComposableArchitecture
    import FilesFeature
    import Localization
    import StoreKit
    import SwiftUI

    /// Mac menu bar: section switching, refresh, new folder and find wired into the root store,
    /// a native App Store rating prompt in the app menu, and the support site in place of the
    /// default Help item (the app ships no help book).
    struct NextExplorerCommands: Commands {
        let store: StoreOf<AppFeature>

        @FocusedValue(\.focusSearchField) private var focusSearchField
        /// Present while the file table has focus; otherwise the Edit menu edits text as usual.
        @FocusedValue(\.browseKeyboardActions) private var fileActions
        @FocusedValue(\.printPreview) private var printPreview
        /// The visible section's toolbar refresh, so ⌘R spins and toasts like clicking it.
        @FocusedValue(\.refreshVisibleScreen) private var refreshVisibleScreen
        @Environment(\.openWindow) private var openWindow

        private static let sections: [(tab: MainTabFeature.Tab, title: String, key: KeyEquivalent)] = [
            (.browse, L10n.Tab.browse, "1"),
            (.favorites, L10n.Tab.favorites, "2"),
            (.shared, L10n.Tab.shared, "3"),
        ]

        var body: some Commands {
            CommandGroup(after: .appInfo) {
                RateAppButton()
            }
            // New Window / New Tab open lightweight Browse windows (MacFolderWindow); the main
            // window stays the only one owning uploads, sync and the session.
            CommandGroup(replacing: .newItem) {
                Button(L10n.Menu.newWindow) { openBrowseWindow(asTab: false) }
                    .keyboardShortcut("n")
                Button(L10n.Menu.newTab) { openBrowseWindow(asTab: true) }
                    .keyboardShortcut("t")
                Divider()
                Button(L10n.Browse.actionNewFolder) { send(.newFolderRequested) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button(L10n.Browse.actionDuplicate) { fileActions?.duplicate() }
                    .keyboardShortcut("d")
                    .disabled(fileActions == nil)
                Button(L10n.Browse.actionGetInfo) { fileActions?.getInfo() }
                    .keyboardShortcut("i")
                    .disabled(fileActions == nil)
            }
            CommandGroup(replacing: .printItem) {
                Button(L10n.OpenWith.print) { printPreview?() }
                    .keyboardShortcut("p")
                    .disabled(printPreview == nil)
            }
            // Undo reverses the last file operation while the file table has focus and one is
            // recorded; otherwise both items go down the responder chain (text fields, editor).
            CommandGroup(replacing: .undoRedo) {
                Button(L10n.Menu.undo) {
                    perform(fileActions?.canUndo == true ? fileActions?.undo : nil, fallback: Selector(("undo:")))
                }
                .keyboardShortcut("z")
                Button(L10n.Menu.redo) { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .pasteboard) {
                Button(L10n.Browse.actionCut) { perform(fileActions?.cut, fallback: #selector(NSText.cut(_:))) }
                    .keyboardShortcut("x")
                Button(L10n.Browse.actionCopy) { perform(fileActions?.copy, fallback: #selector(NSText.copy(_:))) }
                    .keyboardShortcut("c")
                Button(L10n.Browse.actionPaste) {
                    perform(fileActions?.canPaste == true ? fileActions?.paste : nil, fallback: #selector(NSText.paste(_:)))
                }
                .keyboardShortcut("v")
                Button(L10n.Common.delete) { perform(fileActions?.delete, fallback: #selector(NSText.delete(_:))) }
                    .keyboardShortcut(.delete)
                Button(L10n.Select.selectAll) { perform(fileActions?.selectAll, fallback: #selector(NSText.selectAll(_:))) }
                    .keyboardShortcut("a")
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button(L10n.Common.search) { focusSearchField?() }
                    .keyboardShortcut("f")
                    .disabled(focusSearchField == nil)
            }
            CommandGroup(before: .sidebar) {
                ForEach(Self.sections, id: \.tab) { section in
                    Button(section.title) { send(.tabSelected(section.tab)) }
                        .keyboardShortcut(section.key)
                }
                Divider()
                Button(L10n.Menu.refresh) {
                    if let refreshVisibleScreen {
                        refreshVisibleScreen()
                    } else {
                        send(.refreshSelectedTab)
                    }
                }
                .keyboardShortcut("r")
                Button(L10n.Menu.enclosingFolder) { send(.enclosingFolderRequested) }
                    .keyboardShortcut(.upArrow)
                Button(L10n.Common.back) { send(.enclosingFolderRequested) }
                    .keyboardShortcut("[")
                Divider()
            }
            CommandGroup(replacing: .help) {
                SupportButton()
            }
        }

        private func openBrowseWindow(asTab: Bool) {
            guard case .authenticated = store.destination else { return }
            openWindow(value: FolderWindowRoute(
                path: "",
                title: L10n.Browse.navigationTitle,
                tabHostWindowNumber: asTab ? NSApp.keyWindow?.windowNumber : nil
            ))
        }

        /// File table actions when the table has focus, otherwise the standard text action down
        /// the responder chain (search field, rename sheet, editor).
        private func perform(_ fileAction: (() -> Void)?, fallback: Selector) {
            if let fileAction {
                fileAction()
            } else {
                NSApp.sendAction(fallback, to: nil, from: nil)
            }
        }

        /// Menu items stay visible while signed out; they simply do nothing until a session exists.
        private func send(_ action: MainTabFeature.Action) {
            guard case .authenticated = store.destination else { return }
            store.send(.destination(.authenticated(.mainTab(action))))
        }
    }

    /// `requestReview` is only reachable through the environment, so the menu item is a view.
    private struct RateAppButton: View {
        @Environment(\.requestReview) private var requestReview

        var body: some View {
            Button(L10n.Menu.rateApp) { requestReview() }
        }
    }

    private struct SupportButton: View {
        @Environment(\.openURL) private var openURL

        var body: some View {
            Button(L10n.Menu.support) { openURL(AppLinks.support) }
        }
    }
#endif
