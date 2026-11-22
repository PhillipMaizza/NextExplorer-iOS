import SwiftUI

public extension View {
    func dsAlert(isPresented: Binding<Bool>, alert: @escaping () -> DSAlertSheet) -> some View {
        #if os(macOS)
            modifier(MacAlertModifier(isPresented: isPresented, alert: alert))
        #else
            dsSheet(isPresented: isPresented, content: alert)
        #endif
    }
}

#if os(macOS)
    private struct MacAlertModifier: ViewModifier {
        let isPresented: Binding<Bool>
        let alert: () -> DSAlertSheet

        func body(content: Content) -> some View {
            content.sheet(isPresented: isPresented) {
                let sheet = alert()
                MacAlertSheet(
                    title: sheet.title,
                    message: sheet.message,
                    confirmTitle: sheet.confirmTitle,
                    cancelTitle: sheet.dismissTitle,
                    neutralTitle: sheet.neutralTitle,
                    isDestructive: sheet.role == .destructive,
                    isConfirmLoading: sheet.isConfirmLoading,
                    onConfirm: { closing(after: sheet.onConfirm) },
                    onNeutral: sheet.onNeutral.map { action in { closing(after: action) } },
                    onCancel: { closing(after: sheet.onDismiss) }
                )
            }
        }

        private func closing(after action: () -> Void) {
            action()
            isPresented.wrappedValue = false
        }
    }
#endif

#Preview {
    Color.clear
        .previewCanvas(.dialog)
        .dsAlert(isPresented: .constant(true)) {
            DSAlertSheet(
                icon: IconKit.delete,
                title: "Delete “report.pdf”?",
                message: "This cannot be undone.",
                confirmTitle: "Delete",
                dismissTitle: "Cancel",
                role: .destructive,
                closeAccessibilityLabel: "Close",
                onConfirm: {},
                onDismiss: {}
            )
        }
}
