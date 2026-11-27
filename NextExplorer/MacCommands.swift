#if os(macOS)
    import AppFeature
    import AppKit
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
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
        @FocusedValue(\.openMacInspector) private var openMacInspector
        @FocusedValue(\.duplicateBrowseSelection) private var duplicateSelection
        @FocusedValue(\.archiveFolderBack) private var archiveFolderBack
        @FocusedValue(\.printPreview) private var printPreview
        /// The visible section's toolbar refresh, so ⌘R spins and toasts like clicking it.
        @FocusedValue(\.refreshVisibleScreen) private var refreshVisibleScreen
        @FocusedValue(\.toggleMacSidebar) private var toggleMacSidebar
        @FocusedValue(\.closeMacInspector) private var closeMacInspector
        @FocusedValue(\.browseViewOptions) private var viewOptions
        /// Present while an image preview is on screen.
        @FocusedValue(\.previewZoom) private var previewZoom
        /// Present while an extra Browse window is in front; the Go menu then moves that window.
        @FocusedValue(\.folderWindowCommands) private var folderWindow
        @FocusedValue(\.browseCreateAvailability) private var createAvailability
        @Environment(\.openWindow) private var openWindow
        /// Read by `body`, so every menu title is rebuilt in a newly chosen language.
        @AppStorage(AppStorageKeys.appLanguage) private var appLanguage = ""

        private static var sections: [AppMenu.Section] {
            AppMenu.sections(includingOffline: false)
        }

        var body: some Commands {
            CommandGroup(replacing: .sidebar) {
                Button(L10n.Menu.toggleSidebar) { toggleMacSidebar?() }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                    .disabled(toggleMacSidebar == nil)
            }
            // About NextExplorer opens the app's own About window (credits and links).
            CommandGroup(replacing: .appInfo) {
                Button(L10n.Menu.about) { openWindow(id: MacAboutView.windowID) }
                    // Reading the language here rebuilds every menu in a newly chosen one.
                    .id(appLanguage)
            }
            CommandGroup(after: .appInfo) {
                RateAppButton()
            }
            // New Window opens a lightweight Browse window (MacFolderWindow); the main
            // window stays the only one owning uploads, sync and the session.
            CommandGroup(replacing: .newItem) {
                Button(L10n.Menu.newWindow) { openBrowseWindow() }
                    .keyboardShortcut("n")
                Divider()
                Button(L10n.Browse.actionNewFolder) { sendToFrontWindow(
                    { $0.newFolder() },
                    otherwise: .newFolderRequested
                ) }
                .keyboardShortcut(BrowseShortcut.newFolder)
                .disabled(createAvailability?.canCreateFolder == false)
                Button(L10n.Browse.actionNewFile) { sendToFrontWindow({ $0.newFile() }, otherwise: .newFileRequested) }
                    .keyboardShortcut(BrowseShortcut.newFile)
                    .disabled(createAvailability?.canCreateFile == false)
                Divider()
                Button(L10n.Browse.actionDuplicate) {
                    if let duplicate = fileActions?.duplicate {
                        duplicate()
                    } else if !isSheetInFront {
                        duplicateSelection?()
                    }
                }
                .keyboardShortcut("d")
                .disabled(fileActions.map { !$0.canDuplicate } ?? (duplicateSelection == nil))
                Button(L10n.Browse.open) { fileActions?.open() }
                    .keyboardShortcut("o")
                    .disabled(fileActions.map { !$0.canOpen } ?? true)
                Button(L10n.Browse.actionGetInfo) {
                    if let fileActions {
                        fileActions.getInfo()
                    } else {
                        openMacInspector?()
                    }
                }
                .keyboardShortcut("i")
                .disabled(fileActions == nil && openMacInspector == nil)
                Button(L10n.Menu.hideInspector) { closeMacInspector?() }
                    .keyboardShortcut("i", modifiers: [.command, .control])
                    .disabled(closeMacInspector == nil)
            }
            CommandGroup(replacing: .printItem) {
                Button(L10n.OpenWith.print) { printPreview?() }
                    .keyboardShortcut("p")
                    .disabled(printPreview == nil)
            }
            // Undo reverses the last file operation and Redo does the last undone one again while the
            // file table has focus; otherwise both go down the responder chain (text fields, editor).
            // Whether one is waiting is read by the reducer when the action lands, never from a copy
            // made when the table last drew, which could still say no right after an undo.
            CommandGroup(replacing: .undoRedo) {
                Button(L10n.Menu.undo) { perform(fileActions?.undo, fallback: Selector(("undo:"))) }
                    .keyboardShortcut("z")
                Button(L10n.Menu.redo) { perform(fileActions?.redo, fallback: Selector(("redo:"))) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .pasteboard) {
                Button(L10n.Browse.actionCut) { perform(fileActions?.cut, fallback: #selector(NSText.cut(_:))) }
                    .keyboardShortcut("x")
                    .disabled(fileActions.map { !$0.canCut } ?? false)
                Button(L10n.Browse.actionCopy) { perform(fileActions?.copy, fallback: #selector(NSText.copy(_:))) }
                    .keyboardShortcut("c")
                Button(L10n.Browse.actionPaste) {
                    perform(
                        fileActions?.canPaste == true ? fileActions?.paste : nil,
                        fallback: #selector(NSText.paste(_:))
                    )
                }
                .keyboardShortcut(BrowseShortcut.paste)
                .disabled(fileActions.map { !$0.canPaste } ?? false)
                Button(L10n.Common.delete) { perform(fileActions?.delete, fallback: #selector(NSText.delete(_:))) }
                    .keyboardShortcut(.delete)
                    .disabled(fileActions.map { !$0.canDelete } ?? false)
                Button(L10n.Select.selectAll) { perform(
                    fileActions?.selectAll,
                    fallback: #selector(NSText.selectAll(_:))
                ) }
                .keyboardShortcut("a")
            }
            CommandGroup(after: .pasteboard) {
                Button(L10n.Menu.copyPath) { fileActions?.copyPath() }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                    .disabled(fileActions == nil)
                Divider()
                Button(L10n.Common.search) { focusSearchField?() }
                    .keyboardShortcut("f")
                    .disabled(focusSearchField == nil)
                Button(L10n.Spotlight.placeholder) { send(.spotlightToggled) }
                    .keyboardShortcut("k")
            }
            CommandGroup(before: .sidebar) {
                sortMenu
                Toggle(L10n.Settings.toggleShowHiddenFiles, isOn: shouldShowHiddenFiles)
                    .keyboardShortcut(".", modifiers: [.command, .shift])
                Divider()
                Button(L10n.Menu.refresh) {
                    if let refreshVisibleScreen {
                        refreshVisibleScreen()
                    } else {
                        send(.refreshSelectedTab)
                    }
                }
                .keyboardShortcut("r")
                Divider()
                Button(L10n.Menu.zoomIn) { previewZoom?.zoomIn() }
                    .keyboardShortcut("+")
                    .disabled(previewZoom == nil)
                Button(L10n.Menu.zoomOut) { previewZoom?.zoomOut() }
                    .keyboardShortcut("-")
                    .disabled(previewZoom == nil)
                Button(L10n.Menu.zoomToFit) { previewZoom?.zoomToFit() }
                    .keyboardShortcut("0")
                    .disabled(previewZoom == nil)
                Divider()
            }
            // Finder's Go menu: up a level, back, and the sidebar sections.
            CommandMenu(L10n.Menu.go) {
                Button(L10n.Common.back) {
                    if let archiveFolderBack {
                        archiveFolderBack()
                    } else {
                        sendToFrontWindow({ $0.back() }, otherwise: .backRequested)
                    }
                }
                .keyboardShortcut("[", modifiers: .command, localization: .withoutMirroring)
                Button(L10n.Menu.forward) { sendToFrontWindow({ $0.forward() }, otherwise: .forwardRequested) }
                    .keyboardShortcut("]", modifiers: .command, localization: .withoutMirroring)
                Button(L10n.Menu.enclosingFolder) { sendToFrontWindow(
                    { $0.enclosingFolder() },
                    otherwise: .enclosingFolderRequested
                ) }
                .keyboardShortcut(.upArrow)
                Divider()
                Button(L10n.Menu.goToFolder) { sendToFrontWindow({ $0.goToFolder() }, otherwise: .goToFolderPrompted) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                recentFoldersMenu
                Divider()
                ForEach(Self.sections, id: \.tab) { section in
                    Button(section.title) { send(.tabSelected(section.tab)) }
                        .keyboardShortcut(section.key)
                }
            }
            CommandGroup(replacing: .help) {
                SupportButton()
            }
        }

        private var recentFolders: [String] {
            guard case let .authenticated(session) = store.destination else { return [] }
            return session.mainTab.recentFolders
        }

        /// Finder's Go ▸ Recent Folders: the folders opened in Browse this session.
        private var recentFoldersMenu: some View {
            Menu(L10n.Menu.recentFolders) {
                if !recentFolders.isEmpty {
                    ForEach(recentFolders, id: \.self) { path in
                        Button(PersonalSpace.folderTitle(path)) { send(.goToFolderRequested(path)) }
                    }
                    Divider()
                }
                Button(L10n.Menu.clearRecent) { send(.recentFoldersCleared) }
                    .disabled(recentFolders.isEmpty)
            }
        }

        /// Sort By for the visible Browse screen, with a checkmark on the current choice.
        private var sortMenu: some View {
            Menu(L10n.Sort.sheetTitle) {
                Picker(L10n.Sort.sheetTitle, selection: Binding(
                    get: { viewOptions?.sortOption ?? .name },
                    set: { viewOptions?.setSortOption($0) }
                )) {
                    ForEach(BrowseFeature.SortOption.allCases, id: \.self) { Text($0.menuTitle).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Picker(L10n.Sort.sheetTitle, selection: Binding(
                    get: { viewOptions?.sortDirection ?? .ascending },
                    set: { viewOptions?.setSortDirection($0) }
                )) {
                    ForEach(BrowseFeature.SortDirection.allCases, id: \.self) { Text($0.menuTitle).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .disabled(viewOptions == nil)
        }

        /// The signed in account's Show Hidden Files preference, the same one Settings edits.
        private var shouldShowHiddenFiles: Binding<Bool> {
            Binding(
                get: {
                    guard case let .authenticated(session) = store.destination else { return false }
                    return session.mainTab.settings.preferences.shouldShowHiddenFiles
                },
                set: { send(.settings(.setShowHiddenFiles($0))) }
            )
        }

        private func openBrowseWindow() {
            guard case .authenticated = store.destination else { return }
            openWindow(value: FolderWindowRoute(path: "", title: L10n.Browse.navigationTitle))
        }

        /// File table actions when the table has focus, otherwise the standard text action down
        /// the responder chain (search field, rename sheet, editor).
        private func perform(_ fileAction: (() -> Void)?, fallback: Selector) {
            if let fileAction, !isSheetInFront {
                fileAction()
            } else {
                NSApp.sendAction(fallback, to: nil, from: nil)
            }
        }

        /// An extra Browse window in front gets the command; otherwise the main window does.
        private func sendToFrontWindow(
            _ folderAction: (FolderWindowCommands) -> Void,
            otherwise action: MainTabFeature.Action
        ) {
            guard !isSheetInFront else { return }
            if let folderWindow {
                folderAction(folderWindow)
            } else {
                send(action)
            }
        }

        private var isSheetInFront: Bool {
            NSApp.keyWindow?.isSheet == true
        }

        private func send(_ action: MainTabFeature.Action) {
            AppMenu.send(action, to: store)
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
            Button(L10n.Menu.support) { openURL(AppLinks.supportMail) }
        }
    }
#endif
