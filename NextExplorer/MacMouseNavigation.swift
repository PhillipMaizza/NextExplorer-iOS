#if os(macOS)
    import AppKit
    import Localization

    enum MacMouseNavigation {
        private enum SideButton: Int {
            case back = 3
            case forward = 4

            var menuTitle: String {
                switch self {
                case .back: L10n.Common.back
                case .forward: L10n.Menu.forward
                }
            }
        }

        @MainActor
        static func install() -> Any? {
            NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
                guard let button = SideButton(rawValue: event.buttonNumber),
                      let goMenu = NSApp.mainMenu?.item(withTitle: L10n.Menu.go)?.submenu
                else { return event }
                let index = goMenu.indexOfItem(withTitle: button.menuTitle)
                guard index >= 0, goMenu.item(at: index)?.isEnabled == true else { return event }
                goMenu.performActionForItem(at: index)
                return nil
            }
        }
    }
#endif
