#if os(macOS)
    import ComposableArchitecture
    import DesignSystem
    import Localization
    import NetworkClient
    import SwiftUI

    /// The Mac dialog: server, current certificate and, once a file is chosen, its password.
    /// Return installs (or opens the file picker), Esc closes, Remove sits left of Cancel.
    struct ClientCertificateMacForm: View {
        @Bindable var store: StoreOf<ClientCertificateFeature>

        var body: some View {
            MacFormSheet(
                title: L10n.ClientCertificate.title,
                confirmTitle: confirmTitle,
                isConfirmEnabled: store.pendingFile == nil ? store.status != .loading : store.canInstall,
                isWorking: store.isImporting,
                errorMessage: store.failure.map(\.message),
                cancelTitle: L10n.Common.close,
                secondaryTitle: secondaryTitle,
                onSecondary: secondaryAction,
                onCancel: { store.send(.closeTapped) },
                onConfirm: confirmAction
            ) {
                Text(L10n.ClientCertificate.intro)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent(L10n.ClientCertificate.serverLabel) {
                    Text(store.serverName).textSelection(.enabled)
                }
                LabeledContent(L10n.ClientCertificate.certificateLabel) {
                    ClientCertificateSummaryLines(summary: store.installedSummary)
                }
                if let file = store.pendingFile {
                    LabeledContent(L10n.ClientCertificate.fileLabel) {
                        Text(file.name).lineLimit(1).truncationMode(.middle)
                    }
                    SecureField(
                        L10n.ClientCertificate.passwordLabel,
                        text: $store.passphrase.sending(\.passphraseChanged),
                        prompt: Text(L10n.ClientCertificate.passwordPrompt)
                    )
                }
            }
        }

        private var confirmTitle: String {
            if store.pendingFile != nil {
                return L10n.ClientCertificate.install
            }
            return store.installedSummary == nil ? L10n.ClientCertificate.chooseFile : L10n.ClientCertificate.replace
        }

        private var secondaryTitle: String? {
            if store.pendingFile != nil {
                return L10n.ClientCertificate.chooseAnother
            }
            return store.installedSummary == nil ? nil : L10n.ClientCertificate.remove
        }

        private func confirmAction() {
            store.send(store.pendingFile == nil ? .chooseFileTapped : .installTapped)
        }

        private func secondaryAction() {
            store.send(store.pendingFile == nil ? .removeTapped : .chooseFileTapped)
        }
    }

    #Preview("Empty") {
        ClientCertificateSheet(store: .preview(.init(origin: .preview, status: .empty)))
    }

    #Preview("Installed") {
        ClientCertificateSheet(store: .preview(.init(origin: .preview, status: .installed(.preview))))
    }

    #Preview("File picked, wrong password") {
        ClientCertificateSheet(store: .preview(.init(
            origin: .preview,
            status: .installed(.previewExpired),
            pendingFile: .init(name: "phillip-mac.p12", data: Data()),
            importPhase: .failed(.wrongPassword)
        )))
    }
#endif
