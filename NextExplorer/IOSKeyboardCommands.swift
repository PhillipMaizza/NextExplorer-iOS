#if os(iOS)
    import AppFeature
    import AppStorageKeys
    import ComposableArchitecture
    import FilesFeature
    import Localization
    import SwiftUI
    import UIKit

    /// The menu bar and keyboard shortcuts on an iPad (or an iPhone with a keyboard): new items,
    /// the selection's edit commands, search, refresh and moving between folders and tabs. Undo
    /// comes from the system's own Edit menu, which the visible Browse screen feeds.
    struct IOSKeyboardCommands: Commands {
        let store: StoreOf<AppFeature>

        @AppStorage(AppStorageKeys.keepClipboardAfterCopy) private var shouldKeepClipboardAfterCopy = false
        /// Read by `body`, so every menu title is rebuilt in a newly chosen language.
        @AppStorage(AppStorageKeys.appLanguage) private var appLanguage = ""
        @FocusedValue(\.browseCreateAvailability) private var createAvailability

        private static var sections: [AppMenu.Section] {
            AppMenu.sections(includingOffline: true)
        }

        var body: some Commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.Browse.actionNewFolder) { send(.newFolderRequested) }
                    .keyboardShortcut(BrowseShortcut.newFolder)
                    .disabled(createAvailability?.canCreateFolder == false)
                    // Reading the language here rebuilds every menu in a newly chosen one.
                    .id(appLanguage)
                Button(L10n.Browse.actionNewFile) { send(.newFileRequested) }
                    .keyboardShortcut(BrowseShortcut.newFile)
                    .disabled(createAvailability?.canCreateFile == false)
            }
            CommandGroup(replacing: .pasteboard) {
                Button(L10n.Browse.actionCut) {
                    perform(.cut, textAction: #selector(UIResponderStandardEditActions.cut))
                }
                .keyboardShortcut("x")
                Button(L10n.Browse.actionCopy) {
                    perform(.copy, textAction: #selector(UIResponderStandardEditActions.copy))
                }
                .keyboardShortcut("c")
                Button(L10n.Browse.actionPaste) {
                    perform(
                        .paste(keepItemsAfterCopy: shouldKeepClipboardAfterCopy),
                        textAction: #selector(UIResponderStandardEditActions.paste)
                    )
                }
                .keyboardShortcut(BrowseShortcut.paste)
                Button(L10n.Common.delete) {
                    perform(.delete, textAction: #selector(UIResponderStandardEditActions.delete))
                }
                .keyboardShortcut(.delete)
                Button(L10n.Select.selectAll) {
                    perform(.selectAll, textAction: #selector(UIResponderStandardEditActions.selectAll))
                }
                .keyboardShortcut("a")
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button(L10n.Common.search) { SearchFocusRequest.post() }
                    .keyboardShortcut("f")
            }
            CommandGroup(before: .sidebar) {
                Button(L10n.Menu.refresh) { send(.refreshSelectedTab) }
                    .keyboardShortcut("r")
                Divider()
            }
            CommandMenu(L10n.Menu.go) {
                Button(L10n.Common.back) { send(.backRequested) }
                    .keyboardShortcut("[", modifiers: .command, localization: .withoutMirroring)
                Button(L10n.Menu.forward) { send(.forwardRequested) }
                    .keyboardShortcut("]", modifiers: .command, localization: .withoutMirroring)
                Button(L10n.Menu.enclosingFolder) { send(.enclosingFolderRequested) }
                    .keyboardShortcut(.upArrow)
                Divider()
                ForEach(Self.sections, id: \.tab) { section in
                    Button(section.title) { send(.tabSelected(section.tab)) }
                        .keyboardShortcut(section.key)
                }
            }
        }

        /// A text field being edited takes the command first, as its own Edit menu would; with
        /// none, it acts on the visible folder's selection.
        private func perform(_ command: BrowseTabFeature.FolderCommand, textAction: Selector) {
            guard !UIApplication.shared.sendAction(textAction, to: nil, from: nil, for: nil) else { return }
            send(.folderCommandRequested(command))
        }

        private func send(_ action: MainTabFeature.Action) {
            AppMenu.send(action, to: store)
        }
    }
#endif
