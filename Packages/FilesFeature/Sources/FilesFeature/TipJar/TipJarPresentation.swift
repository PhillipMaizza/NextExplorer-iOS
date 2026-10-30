import ComposableArchitecture
import CoreModels
import DesignSystem
import SwiftUI

/// The tip jar sheet and its thank you toast. iOS hosts them in Settings, where "Buy me a
/// coffee" sits. On the Mac both the main window (the sidebar's coffee link) and the Settings
/// window (its Info pane) host them, and the one that was active when the jar was opened shows
/// it and its toast.
struct TipJarPresentation: ViewModifier {
    @Bindable var store: StoreOf<SettingsFeature>
    @State private var tipToast: DSToastMessage?

    #if os(macOS)
        @State private var isSheetOwner = false
        /// Kept past the sheet closing, since the thank you toast follows the purchase.
        @State private var isToastOwner = false
    #endif

    private var shouldShowSheet: Bool {
        #if os(macOS)
            isSheetOwner
        #else
            true
        #endif
    }

    private var shouldShowToast: Bool {
        #if os(macOS)
            isToastOwner
        #else
            true
        #endif
    }

    private var tipJarStore: Binding<StoreOf<TipJarFeature>?> {
        Binding(
            get: { shouldShowSheet ? store.scope(state: \.tipJar, action: \.tipJar.presented) : nil },
            set: { newValue in
                if newValue == nil, store.tipJar != nil {
                    store.send(.tipJar(.dismiss))
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .dsSheet(item: tipJarStore) { tipStore in
                TipJarSheet(store: tipStore) { store.send(.tipJar(.dismiss)) }
            }
            .dsToast($tipToast)
            .onChange(of: store.tipToast) { _, message in
                guard let message, shouldShowToast else { return }
                tipToast = .success(message)
                store.send(.tipToastShown)
            }
        #if os(macOS)
            .onWindowPromptChange(of: store.tipJar != nil) { isPending, isOwner in
                isSheetOwner = isOwner
                if isPending {
                    isToastOwner = isOwner
                }
            }
        #endif
    }
}

#Preview("Tip jar") {
    var state = SettingsFeature.State(
        serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
        user: User(id: "preview-user", username: "jdoe", email: "jane.doe@example.com")
    )
    state.tipJar = TipJarFeature.State()
    return Color.clear
        .frame(width: 600, height: 600)
        .modifier(TipJarPresentation(store: Store(initialState: state) { SettingsFeature() }))
}
