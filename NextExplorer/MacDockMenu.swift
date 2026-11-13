#if os(macOS)
    import AppFeature
    import AppKit
    import ComposableArchitecture
    import FilesFeature
    import Localization

    /// The Dock icon's menu: the folders opened recently in Browse, like Finder's, each one
    /// reopening in the main window. Also asks before quitting mid transfer.
    final class MacAppDelegate: NSObject, NSApplicationDelegate {
        @MainActor
        func applicationDockMenu(_: NSApplication) -> NSMenu? {
            guard case let .authenticated(session) = NextExplorerApp.store.destination,
                  !session.mainTab.recentFolders.isEmpty else { return nil }
            let menu = NSMenu()
            for path in session.mainTab.recentFolders {
                let item = NSMenuItem(
                    title: (path as NSString).lastPathComponent,
                    action: #selector(openRecentFolder(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = path
                item.toolTip = path
                menu.addItem(item)
            }
            return menu
        }

        /// Like Safari with downloads running: quitting mid transfer asks first, since it stops
        /// every upload and download in flight.
        @MainActor
        func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
            guard case let .authenticated(session) = NextExplorerApp.store.destination,
                  session.mainTab.hasTransfersInFlight
            else { return .terminateNow }
            let alert = NSAlert()
            alert.messageText = L10n.Menu.quitTransfersTitle
            alert.informativeText = L10n.Menu.quitTransfersMessage
            alert.addButton(withTitle: L10n.Menu.quitTransfersConfirm)
            alert.addButton(withTitle: L10n.Common.cancel)
            return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
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
