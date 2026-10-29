#if os(macOS)
    import ComposableArchitecture
    import DesignSystem
    import SwiftUI

    /// The Settings screens for the Mac's own Settings window (⌘,), drawn as native grouped
    /// forms. The sidebar has no Settings section on the Mac.
    public struct MacSettingsContent: View {
        let store: StoreOf<MainTabFeature>

        public init(store: StoreOf<MainTabFeature>) {
            self.store = store
        }

        public var body: some View {
            SettingsView(store: store.scope(state: \.settings, action: \.settings))
                .groupedListUsesNativeForm()
        }
    }
#endif
