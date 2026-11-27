#if os(macOS)
    import AppKit
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    extension OfflineFileStore {
        func keptCopy(of item: FileItem) -> @Sendable () -> URL? {
            let store = self
            return { store.localURLIgnoringStaleness(item) }
        }
    }

    @MainActor
    enum MacLocalFileAction: CaseIterable {
        case share
        case copy
        case save

        var title: String {
            switch self {
            case .share: L10n.Common.share
            case .copy: L10n.Browse.actionCopy
            case .save: SaveActionStyle.title
            }
        }

        var menuIcon: Image {
            switch self {
            case .share: MenuIcon.systemShare.image
            case .copy: MenuIcon.copy.image
            case .save: MenuIcon.download.image
            }
        }

        var panelIcon: Image {
            switch self {
            case .share: MenuIcon.systemShare.panelImage
            case .copy: MenuIcon.duplicate.panelImage
            case .save: MenuIcon.download.panelImage
            }
        }

        func perform(resolve: @escaping @Sendable () -> URL?) {
            @Dependency(\.saveLocationPicker) var saveLocationPicker
            let picker = saveLocationPicker
            let window = NSApp.keyWindow
            let anchor = window.map { NSRect(origin: $0.mouseLocationOutsideOfEventStream, size: .zero) }
            Task {
                guard let url = await Task.detached(priority: .userInitiated, operation: resolve).value else {
                    NSSound.beep()
                    return
                }
                switch self {
                case .share:
                    guard let view = window?.contentView, let anchor else { return }
                    NSSharingServicePicker(items: [url]).show(relativeTo: anchor, of: view, preferredEdge: .minY)
                case .copy:
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([url as NSURL])
                case .save:
                    guard let destination = await picker.chooseFile(url.lastPathComponent) else { return }
                    let copied: Void? = try? await Task.detached(priority: .userInitiated) {
                        try MacDownloadSaving.copy(url, to: destination)
                    }.value
                    if copied == nil {
                        NSSound.beep()
                    }
                }
            }
        }
    }

    struct MacLocalFileMenuItems: View {
        let resolve: @Sendable () -> URL?

        var body: some View {
            ForEach(MacLocalFileAction.allCases, id: \.self) { action in
                Button {
                    action.perform(resolve: resolve)
                } label: {
                    Label { Text(action.title) } icon: { action.menuIcon }
                }
                .tint(.primaryDS)
            }
        }
    }

    struct MacLocalFilePanelRows: View {
        let resolve: @Sendable () -> URL?

        var body: some View {
            ForEach(MacLocalFileAction.allCases, id: \.self) { action in
                MacActionMenuButton(action.title, icon: action.panelIcon) {
                    action.perform(resolve: resolve)
                }
            }
        }
    }

    #Preview("Context menu") {
        Menu(L10n.Common.more) {
            MacLocalFileMenuItems { nil }
        }
        .padding()
        .background(Color.macCard)
    }

    #Preview("Panel") {
        MacActionMenuPanel {
            MacLocalFilePanelRows { nil }
        }
        .padding()
        .background(Color.macCard)
    }
#endif
