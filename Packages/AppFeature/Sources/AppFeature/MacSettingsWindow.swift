#if os(macOS)
    import ComposableArchitecture
    import FilesFeature
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 640
        static let minHeight: CGFloat = 600
        static let idealHeight: CGFloat = 680
    }

    /// Content of the Mac's Settings window. It shows the signed in session's settings and
    /// closes when there is none (signed out or before sign in), like the extra Browse windows.
    public struct MacSettingsWindow: View {
        let mainStore: StoreOf<AppFeature>
        @Environment(\.dismiss) private var dismiss

        public init(mainStore: StoreOf<AppFeature>) {
            self.mainStore = mainStore
        }

        public var body: some View {
            Group {
                if let session = mainStore.scope(state: \.destination.authenticated, action: \.destination.authenticated) {
                    MacSettingsContent(store: session.scope(state: \.mainTab, action: \.mainTab))
                } else {
                    Color.clear.onAppear { dismiss() }
                }
            }
            // Like the main window, never the compact (phone) layout and its phone only options.
            .environment(\.horizontalSizeClass, .regular)
            .frame(width: Metrics.width)
            .frame(minHeight: Metrics.minHeight, idealHeight: Metrics.idealHeight)
            .onChange(of: mainStore.currentAccountID) { _, newValue in
                if newValue == nil {
                    dismiss()
                }
            }
        }
    }
#endif
