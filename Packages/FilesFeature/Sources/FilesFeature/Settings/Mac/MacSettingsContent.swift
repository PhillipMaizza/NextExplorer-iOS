#if os(macOS)
    import ComposableArchitecture
    import CoreModels
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

    #Preview {
        MacSettingsContent(store: Store(initialState: MainTabFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            user: User(id: "preview-user", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe", roles: [UserRole.admin])
        )) { MainTabFeature() } withDependencies: { $0.filesClient = .previewValue })
            .frame(width: 920, height: 560)
    }
#endif
