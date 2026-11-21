import CoreModels
import DesignSystem
import SwiftUI

/// The sign in form's haptics: an error buzz for any error, and the Test connection result.
struct LoginHapticsModifier: ViewModifier {
    let errorMessage: String?
    let connectionPhase: LoginFormFeature.ConnectionPhase

    func body(content: Content) -> some View {
        let withErrorFeedback = content.hapticFeedback(.error, trigger: errorMessage) { _, newValue in
            newValue != nil
        }
        return withErrorFeedback.modifier(ConnectionPhaseHapticsModifier(connectionPhase: connectionPhase))
    }
}

private struct ConnectionPhaseHapticsModifier: ViewModifier {
    let connectionPhase: LoginFormFeature.ConnectionPhase

    func body(content: Content) -> some View {
        content
            .hapticFeedback(.success, trigger: connectionPhase) { _, newValue in newValue == .success }
            .hapticFeedback(.error, trigger: connectionPhase) { _, newValue in newValue == .failure }
    }
}

#Preview {
    Text(verbatim: "")
        .modifier(LoginHapticsModifier(errorMessage: nil, connectionPhase: .success))
}
