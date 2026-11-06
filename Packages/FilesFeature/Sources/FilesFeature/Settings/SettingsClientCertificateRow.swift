import ClientCertificateFeature
import ComposableArchitecture
import DesignSystem
import Localization
import SwiftUI

/// The Settings row for the client certificate presented to this account's server (mTLS),
/// with the installed certificate's name as its value. Opens the shared certificate sheet.
struct SettingsClientCertificateRow: View {
    let store: StoreOf<SettingsFeature>

    var body: some View {
        DSNavigationRow(
            title: L10n.Settings.clientCertificate,
            icon: IconKit.accessRules,
            accessory: .detail(store.clientCertificateStatus.settingsDetail)
        ) {
            store.send(.clientCertificateButtonTapped)
        }
        .disabled(store.isSigningOut)
    }
}

extension ClientCertificateFeature.Status {
    /// The value beside the Settings row: the certificate's name, "None", or blank while loading.
    var settingsDetail: String {
        switch self {
        case .loading: ""
        case .empty: L10n.Settings.clientCertificateNone
        case let .installed(summary): summary.subject
        }
    }
}

#Preview("None") {
    List {
        SettingsClientCertificateRow(store: .settingsPreview(status: .empty))
    }
}

#Preview("Installed") {
    List {
        SettingsClientCertificateRow(store: .settingsPreview(status: .installed(.init(subject: "Phillip iPhone"))))
    }
}

private extension StoreOf<SettingsFeature> {
    static func settingsPreview(status: ClientCertificateFeature.Status) -> StoreOf<SettingsFeature> {
        var state = SettingsFeature.State(
            serverURL: URL(string: "https://files.example.com")!,
            user: .init(id: "1", username: "phillip", email: nil, roles: [])
        )
        state.clientCertificateStatus = status
        return Store(initialState: state) { SettingsFeature() }
    }
}
