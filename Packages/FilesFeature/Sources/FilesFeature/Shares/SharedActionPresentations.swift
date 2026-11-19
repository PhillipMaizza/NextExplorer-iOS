import ComposableArchitecture
import DesignSystem
import Localization
import SwiftUI

/// Delete for a share, plus Edit as a sheet on the Mac, presented over whatever started them so they
/// stack on top: the detail sheet on iOS, the table on the Mac. Only one surface applies it at a
/// time. On iOS Edit is a page the share page pushes instead.
struct SharedActionPresentations: ViewModifier {
    @Bindable var store: StoreOf<SharedFeature>
    @Binding var toast: DSToastMessage?

    private var deleteConfirmationBinding: Binding<Bool> {
        // No op setter: the alert is dismiss disabled and only closes through one of
        // `DSAlertSheet`'s own buttons, each of which drives the reducer directly. This keeps
        // SwiftUI from firing a stray dismiss action into a torn down presentation.
        Binding(get: { store.deleteConfirmationShare != nil }, set: { _ in })
    }

    func body(content: Content) -> some View {
        content
        #if os(macOS)
            .dsSheet(item: $store.scope(state: \.editSheet, action: \.editSheet)) { editStore in
                MacEditShareSheet(store: editStore)
            }
        #endif
            .dsAlert(isPresented: deleteConfirmationBinding) {
                DSAlertSheet(
                    icon: IconKit.delete,
                    title: L10n.Shared.deleteTitle,
                    message: L10n.Shared.deleteMessage,
                    confirmTitle: L10n.Common.delete,
                    dismissTitle: L10n.Common.cancel,
                    role: .destructive,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: { store.send(.deleteConfirmed) },
                    onDismiss: { store.send(.deleteCancelled) }
                )
            }
            .sharedActionToast(store: store, toast: $toast)
    }
}

extension View {
    /// Shows a failed delete or refresh as a red toast, or a saved edit as a green one, once, then
    /// clears it so the same outcome toasts again. `isActive` keeps a covered surface from toasting
    /// under the one on top.
    func sharedActionToast(
        store: StoreOf<SharedFeature>,
        toast: Binding<DSToastMessage?>,
        isActive: Bool = true
    ) -> some View {
        onChange(of: store.actionErrorMessage) { _, message in
            guard isActive, let message else { return }
            toast.wrappedValue = .failure(message)
            store.send(.actionToastShown)
        }
        .onChange(of: store.actionSuccessMessage) { _, message in
            guard isActive, let message else { return }
            toast.wrappedValue = .success(message)
            store.send(.actionToastShown)
        }
    }
}
