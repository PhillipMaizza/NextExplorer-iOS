import DesignSystem
import SwiftUI

private struct FeatureToastModifier: ViewModifier {
    let error: String?
    let success: String?
    var extraBottomInset: CGFloat = 0

    @State private var message: DSToastMessage?

    func body(content: Content) -> some View {
        content
            .dsToast($message, extraBottomInset: extraBottomInset)
            .onChange(of: error) { _, newValue in
                if let newValue {
                    message = DSToastMessage(icon: IconKit.errorFill, text: newValue)
                }
            }
            .onChange(of: success) { _, newValue in
                if let newValue {
                    message = .success(newValue)
                }
            }
    }
}

extension View {
    func featureToast(error: String?, success: String? = nil, extraBottomInset: CGFloat = 0) -> some View {
        modifier(FeatureToastModifier(error: error, success: success, extraBottomInset: extraBottomInset))
    }
}
