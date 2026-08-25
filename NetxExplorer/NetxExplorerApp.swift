import AppFeature
import ComposableArchitecture
import DesignSystem
import SwiftUI

@main
struct NetxExplorerApp: App {
    static let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    init() {
        DesignSystemFonts.registerAll()
    }

    var body: some Scene {
        WindowGroup {
            AppView(store: Self.store)
                .tint(Color.accent)
        }
    }
}
