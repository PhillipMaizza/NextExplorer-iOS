import SwiftUI

public extension View {
    /// Presents a `DSAlertSheet` confirmation: its card sheet on iOS, a native alert built from
    /// the same title, message, buttons and roles on the Mac. The buttons drive the callbacks
    /// directly, so a binding with a no op setter works on both.
    func dsAlert(isPresented: Binding<Bool>, alert: @escaping () -> DSAlertSheet) -> some View {
        #if os(macOS)
            modifier(NativeAlertModifier(isPresented: isPresented, alert: alert))
        #else
            dsSheet(isPresented: isPresented, content: alert)
        #endif
    }
}

#if os(macOS)
    private struct NativeAlertModifier: ViewModifier {
        let isPresented: Binding<Bool>
        let alert: () -> DSAlertSheet

        func body(content: Content) -> some View {
            let sheet = alert()
            content.alert(sheet.title, isPresented: isPresented) {
                Button(sheet.confirmTitle, role: sheet.role == .destructive ? .destructive : nil, action: sheet.onConfirm)
                if let neutralTitle = sheet.neutralTitle, let onNeutral = sheet.onNeutral {
                    Button(neutralTitle, action: onNeutral)
                }
                Button(sheet.dismissTitle, role: .cancel, action: sheet.onDismiss)
            } message: {
                if let message = sheet.message {
                    Text(message)
                }
            }
        }
    }
#endif
