import DesignSystem
import Localization
import NetworkClient
import SwiftUI

/// The installed certificate at a glance: who it identifies, who issued it and when it
/// expires, or a plain "none" line. Shared by the sheet on both platforms.
struct ClientCertificateSummaryLines: View {
    let summary: ClientCertificateSummary?
    var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: .space4) {
            if let summary {
                Text(summary.subject.isEmpty ? L10n.ClientCertificate.title : summary.subject)
                    .type(.body2(.semibold))
                if let issuer = summary.issuer {
                    Text(L10n.ClientCertificate.issuedBy(issuer))
                        .type(.body3(.regular), style: .secondary)
                }
                if let expiresAt = summary.expiresAt {
                    let formatted = expiresAt.formatted(date: .abbreviated, time: .omitted)
                    if summary.isExpired(now: now) {
                        Text(L10n.ClientCertificate.expired(formatted))
                            .type(.body3(.semibold), style: .error)
                    } else {
                        Text(L10n.ClientCertificate.expires(formatted))
                            .type(.body3(.regular), style: .secondary)
                    }
                }
            } else {
                Text(L10n.ClientCertificate.none)
                    .type(.body2(.regular), style: .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Says what to do about a certificate that has expired or will within two weeks; nothing for
/// one that is fine. Shared by the sheet on both platforms.
public struct ClientCertificateExpiryWarning: View {
    let summary: ClientCertificateSummary?
    var now = Date()

    public init(summary: ClientCertificateSummary?, now: Date = Date()) {
        self.summary = summary
        self.now = now
    }

    public var body: some View {
        if let summary, let text = Self.text(for: summary, now: now) {
            Text(text)
                .type(.body3(.regular), style: .warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func text(for summary: ClientCertificateSummary, now: Date) -> String? {
        switch summary.expiry(now: now) {
        case .valid:
            nil
        case .expiringSoon:
            summary.expiresAt.map { L10n.ClientCertificate.expiringSoonWarning($0.formatted(
                date: .abbreviated,
                time: .omitted
            )) }
        case .expired:
            L10n.ClientCertificate.expiredWarning
        }
    }
}

extension ClientCertificateFeature.Failure {
    var message: String {
        switch self {
        case .wrongPassword: L10n.ClientCertificate.errorWrongPassword
        case .invalidFile: L10n.ClientCertificate.errorInvalidFile
        case .noIdentity: L10n.ClientCertificate.errorNoIdentity
        case .storage: L10n.ClientCertificate.errorStorage
        case .unreadable: L10n.ClientCertificate.errorUnreadable
        case .removal: L10n.ClientCertificate.errorRemove
        }
    }
}

extension ClientCertificateSummary {
    static let preview = ClientCertificateSummary(
        subject: "Phillip iPhone",
        issuer: "Homelab Client CA",
        expiresAt: Date(timeIntervalSince1970: 1_830_000_000)
    )

    static let previewExpired = ClientCertificateSummary(
        subject: "Old Laptop",
        issuer: "Homelab Client CA",
        expiresAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

#Preview("Installed") {
    ClientCertificateSummaryLines(summary: .preview)
        .dsCard()
        .padding(.space24)
}

#Preview("Expired") {
    ClientCertificateSummaryLines(summary: .previewExpired)
        .dsCard()
        .padding(.space24)
}

#Preview("Expiring soon") {
    let summary = ClientCertificateSummary(
        subject: "Phillip iPhone",
        expiresAt: Date().addingTimeInterval(5 * 24 * 60 * 60)
    )
    VStack(alignment: .leading, spacing: .space8) {
        ClientCertificateSummaryLines(summary: summary)
        ClientCertificateExpiryWarning(summary: summary)
    }
    .dsCard()
    .padding(.space24)
}

#Preview("None") {
    ClientCertificateSummaryLines(summary: nil)
        .dsCard()
        .padding(.space24)
}
