import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// Offered on the server page after the server refused the handshake over its client
/// certificate: opens the certificate sheet for that exact server.
struct LoginCertificateButton: View {
    let isRejected: Bool
    let action: () -> Void

    var body: some View {
        DSButton(
            isRejected ? L10n.Login.manageClientCertificate : L10n.Login.addClientCertificate,
            icon: IconKit.accessRules,
            style: .outline,
            action: action
        )
        .accessibilityIdentifier(AccessibilityIdentifiers.Login.clientCertificateButton)
    }
}

#Preview("Required") {
    LoginCertificateButton(isRejected: false, action: {})
        .padding(.space24)
}

#Preview("Rejected") {
    LoginCertificateButton(isRejected: true, action: {})
        .padding(.space24)
}
