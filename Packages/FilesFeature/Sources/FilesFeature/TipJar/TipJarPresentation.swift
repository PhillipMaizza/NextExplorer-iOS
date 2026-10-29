import ComposableArchitecture
import DesignSystem
import SwiftUI

/// The tip jar sheet and its thank you toast. iOS hosts them in Settings, where "Buy me a
/// coffee" sits; the Mac hosts them on the main window, beside the sidebar's coffee link.
struct TipJarPresentation: ViewModifier {
    @Bindable var store: StoreOf<SettingsFeature>
    @State private var tipToast: DSToastMessage?

    func body(content: Content) -> some View {
        content
            .dsSheet(item: $store.scope(state: \.tipJar, action: \.tipJar)) { tipStore in
                TipJarSheet(store: tipStore) { store.send(.tipJar(.dismiss)) }
            }
            .dsToast($tipToast)
            .onChange(of: store.tipToast) { _, message in
                guard let message else { return }
                tipToast = .success(message)
                store.send(.tipToastShown)
            }
    }
}
