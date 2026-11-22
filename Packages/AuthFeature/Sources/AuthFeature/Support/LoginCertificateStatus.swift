import ClientCertificateFeature
import DesignSystem
import Localization
import NetworkClient
import SwiftUI

/// "Using client certificate X · Change" on the login pages, so someone who picked the wrong
/// file can swap it before the server refuses it. Includes the expiry warning when it applies.
struct LoginCertificateStatus: View {
    let summary: ClientCertificateSummary
    let onChange: () -> Void

    var body: some View {
        #if os(macOS)
            VStack(alignment: .leading, spacing: .space8) {
                HStack(spacing: .space12) {
                    IconKit.accessRules
                        .foregroundStyle(Color.accentText)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: .space2) {
                        Text(L10n.Login.clientCertificateAdded)
                            .type(.body3(.semibold))
                        Text(summary.subject)
                            .type(.caption(.regular), style: .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    Button(L10n.Login.changeClientCertificate, action: onChange)
                        .buttonStyle(.macDS(.secondary, size: .small))
                }
                .padding(.space12)
                .background(
                    RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                        .fill(Color.macRow)
                )
                ClientCertificateExpiryWarning(summary: summary)
            }
        #else
            iosBody
        #endif
    }

    #if os(iOS)
        private var iosBody: some View {
            VStack(alignment: .leading, spacing: .space4) {
                HStack(alignment: .firstTextBaseline, spacing: .space8) {
                    IconKit.accessRules
                        .foregroundStyle(Color.accentText)
                        .accessibilityHidden(true)
                    Text(L10n.Login.usingClientCertificate(summary.subject))
                        .type(.body3(.regular), style: .secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(L10n.Login.changeClientCertificate, action: onChange)
                        .buttonStyle(.borderless)
                        .type(.body3(.semibold), style: .custom(.accentText))
                }
                ClientCertificateExpiryWarning(summary: summary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    #endif
}

#Preview("In use") {
    LoginCertificateStatus(summary: .init(subject: "Example iPhone"), onChange: {})
        .padding(.space24)
}

#Preview("Expiring soon") {
    LoginCertificateStatus(
        summary: .init(subject: "Example iPhone", expiresAt: Date().addingTimeInterval(4 * 24 * 60 * 60)),
        onChange: {}
    )
    .padding(.space24)
}
