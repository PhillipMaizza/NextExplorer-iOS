import DesignSystem
import SwiftUI

/// Bridges a reducer's transient message strings to a bottom toast, so a screen doesn't need
/// its own `@State` + `.onChange` + `.dsToast` boilerplate. Pass the store's optional
/// `error` / `success` strings; whenever one *changes* to a non-nil value it's shown, and
/// `DSToast`'s own timer clears it. (Like the rest of the app's toasts, two identical
/// messages in a row don't re-trigger — the message is already on screen saying the same
/// thing.)
private struct FeatureToastModifier: ViewModifier {
    let error: String?
    let success: String?
    var extraBottomInset: CGFloat = 0

    @State private var message: DSToastMessage?

    func body(content: Content) -> some View {
        content
            .dsToast($message, extraBottomInset: extraBottomInset)
            .onChange(of: error) { _, newValue in
                if let newValue { message = DSToastMessage(icon: IconKit.warning, text: newValue) }
            }
            .onChange(of: success) { _, newValue in
                if let newValue { message = .success(newValue) }
            }
    }
}

extension View {
    func featureToast(error: String?, success: String? = nil, extraBottomInset: CGFloat = 0) -> some View {
        modifier(FeatureToastModifier(error: error, success: success, extraBottomInset: extraBottomInset))
    }
}
