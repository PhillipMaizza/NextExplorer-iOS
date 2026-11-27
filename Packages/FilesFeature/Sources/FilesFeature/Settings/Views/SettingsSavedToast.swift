import ComposableArchitecture
import DesignSystem
import SwiftUI

struct SettingsSavedToast: ViewModifier {
    let store: StoreOf<SettingsFeature>
    @State private var toast: DSToastMessage?

    func body(content: Content) -> some View {
        content
            .dsToast($toast)
            .onChange(of: store.savedToast) { _, message in
                guard let message else { return }
                toast = .success(message)
                store.send(.savedToastShown)
            }
    }
}
