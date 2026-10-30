import AuthFeature
import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

#if os(macOS)
    private enum Metrics {
        static let width: CGFloat = 520
        static let height: CGFloat = 640
    }
#endif

/// The login sheet for adding another server while signed in. On the Mac both the main
/// window and the Settings window host it, and the one that was active when Add Account was
/// chosen shows it, so it never opens behind (or brings forward) the other window.
struct AddAccountSheet: ViewModifier {
    let store: StoreOf<AppFeature>

    #if os(macOS)
        @State private var isSheetOwner = false
    #endif

    private var shouldShowSheet: Bool {
        #if os(macOS)
            isSheetOwner
        #else
            true
        #endif
    }

    /// The Mac adds an account in a dialog sized sheet, where the accent flood into the app has
    /// nothing to reveal.
    private var shouldAddAccountInDialog: Bool {
        #if os(macOS)
            true
        #else
            false
        #endif
    }

    private var sheetStore: Binding<StoreOf<LoginFormFeature>?> {
        Binding(
            get: { shouldShowSheet ? store.scope(state: \.addAccount, action: \.addAccount.presented) : nil },
            set: { newValue in
                if newValue == nil, store.addAccount != nil {
                    store.send(.addAccount(.dismiss))
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: sheetStore, onDismiss: { store.send(.addAccountSheetDismissed) }) { addAccountStore in
                LoginFormView(store: addAccountStore, autoFocus: true, shouldFloodIntoApp: !shouldAddAccountInDialog)
                #if os(macOS)
                    // A Mac sheet sizes to its content's ideal size, which the flexible login
                    // layout collapses to nothing; and there is no swipe down, so it needs Cancel.
                    .frame(width: Metrics.width, height: Metrics.height)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.Common.cancel) { store.send(.addAccount(.dismiss)) }
                        }
                    }
                #endif
            }
        #if os(macOS)
            .onWindowPromptChange(of: store.addAccount != nil) { _, isOwner in
                isSheetOwner = isOwner
            }
        #endif
    }
}

#Preview("Add account") {
    Color.clear
        .frame(width: 600, height: 700)
        .modifier(AddAccountSheet(store: .previewSignedIn(addAccount: true)))
}
