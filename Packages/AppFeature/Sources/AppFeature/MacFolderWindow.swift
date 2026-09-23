#if os(macOS)
    import AppKit
    import ComposableArchitecture
    import DesignSystem
    import FilesFeature
    import SwiftUI

    private enum Metrics {
        static let minWidth: CGFloat = 640
        static let minHeight: CGFloat = 420
    }

    /// Content of an extra Mac Browse window or tab. It borrows the main window's session and
    /// hands uploads, favorites changes and tab jumps back to the main store. It closes itself
    /// on sign out or an account switch, so no window keeps showing a previous account's files.
    public struct MacFolderWindow: View {
        let route: FolderWindowRoute
        let mainStore: StoreOf<AppFeature>

        @State private var store: StoreOf<FolderWindowFeature>?
        @State private var accountID: String?
        @Environment(\.dismiss) private var dismiss

        public init(route: FolderWindowRoute, mainStore: StoreOf<AppFeature>) {
            self.route = route
            self.mainStore = mainStore
        }

        public var body: some View {
            Group {
                if let store {
                    FolderWindowView(store: store)
                } else {
                    Color.clear
                }
            }
            .environment(\.horizontalSizeClass, .regular)
            .frame(minWidth: Metrics.minWidth, minHeight: Metrics.minHeight)
            .background(WindowTabJoiner(hostWindowNumber: route.tabHostWindowNumber))
            .onAppear(perform: start)
            .onChange(of: mainStore.currentAccountID) { _, newValue in
                if newValue == nil || newValue != accountID {
                    dismiss()
                }
            }
        }

        private func start() {
            guard store == nil else { return }
            guard case let .authenticated(session) = mainStore.destination,
                  let account = mainStore.currentAccountID
            else {
                dismiss()
                return
            }
            accountID = account
            let mainStore = mainStore
            let windowStore = Store(initialState: FolderWindowFeature.State(serverURL: session.mainTab.browse.root.serverURL)) {
                FolderWindowFeature { delegate in
                    await MainActor.run {
                        guard case .authenticated = mainStore.destination else { return }
                        mainStore.send(.destination(.authenticated(.mainTab(.browse(.delegate(delegate))))))
                    }
                }
            }
            if !route.path.isEmpty {
                windowStore.send(.browse(.navigateToDirectory(path: route.path, title: route.title)))
            }
            store = windowStore
        }
    }

    /// Joins this window to `hostWindowNumber`'s tab group the first time it lands in a window,
    /// which is how ⌘T and "Open in New Tab" open a tab rather than a separate window.
    private struct WindowTabJoiner: NSViewRepresentable {
        let hostWindowNumber: Int?

        func makeNSView(context _: Context) -> NSView {
            JoinerView(hostWindowNumber: hostWindowNumber)
        }

        func updateNSView(_: NSView, context _: Context) {}

        private final class JoinerView: NSView {
            private let hostWindowNumber: Int?
            private var didJoin = false

            init(hostWindowNumber: Int?) {
                self.hostWindowNumber = hostWindowNumber
                super.init(frame: .zero)
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                nil
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard !didJoin, let window, let hostWindowNumber,
                      let host = NSApp.window(withWindowNumber: hostWindowNumber), host != window
                else { return }
                didJoin = true
                // Deferred out of the layout pass this callback runs in: regrouping windows
                // mid pass lets SwiftUI replay a toolbar update and AppKit rejects the
                // duplicate item.
                DispatchQueue.main.async { [weak window] in
                    guard let window else { return }
                    host.addTabbedWindow(window, ordered: .above)
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
#endif
