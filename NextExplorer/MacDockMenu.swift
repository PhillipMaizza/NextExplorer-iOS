#if os(macOS)
    import AppFeature
    import AppKit
    import ComposableArchitecture
    import FilesFeature

    /// The Dock icon's menu: the folders opened recently in Browse, like Finder's, each one
    /// reopening in the main window.
    final class MacAppDelegate: NSObject, NSApplicationDelegate {
        @MainActor
        func applicationDockMenu(_: NSApplication) -> NSMenu? {
            guard case let .authenticated(session) = NextExplorerApp.store.destination,
                  !session.mainTab.recentFolders.isEmpty else { return nil }
            let menu = NSMenu()
            for path in session.mainTab.recentFolders {
                let item = NSMenuItem(title: (path as NSString).lastPathComponent, action: #selector(openRecentFolder(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = path
                item.toolTip = path
                menu.addItem(item)
            }
            return menu
        }

        @MainActor @objc
        private func openRecentFolder(_ sender: NSMenuItem) {
            guard let path = sender.representedObject as? String,
                  case .authenticated = NextExplorerApp.store.destination else { return }
            NSApp.activate()
            NextExplorerApp.store.send(.destination(.authenticated(.mainTab(.goToFolderRequested(path)))))
        }
    }
#endif
