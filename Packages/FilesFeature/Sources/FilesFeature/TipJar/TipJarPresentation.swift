import ComposableArchitecture
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
        @Environment(\.appearsActive) private var appearsActive
        @State private var ownsSheet = false
        /// Kept past the sheet closing, since the thank you toast follows the purchase.
        @State private var ownsToast = false
    #endif

    private var showsSheet: Bool {
        #if os(macOS)
            ownsSheet
        #else
            true
        #endif
    }

    private var showsToast: Bool {
        #if os(macOS)
            ownsToast
        #else
            true
        #endif
    }

    private var tipJarStore: Binding<StoreOf<TipJarFeature>?> {
        Binding(
            get: { showsSheet ? store.scope(state: \.tipJar, action: \.tipJar.presented) : nil },
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
                guard let message, showsToast else { return }
                tipToast = .success(message)
                store.send(.tipToastShown)
            }
        #if os(macOS)
            .onChange(of: store.tipJar != nil) { _, pending in
                ownsSheet = pending && appearsActive
                if pending {
                    ownsToast = ownsSheet
                }
            }
        #endif
    }
}
