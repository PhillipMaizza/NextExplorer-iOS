import ComposableArchitecture
import DesignSystem
import Localization
import NetworkClient
import SwiftUI
import UniformTypeIdentifiers

private enum Metrics {
    static let contentSpacing: CGFloat = .space24
    static let sectionSpacing: CGFloat = .space8
    static let horizontalPadding: CGFloat = .space24
    static let verticalPadding: CGFloat = .space24
    static let footerSpacing: CGFloat = .space12
    static let maxHeightFraction: CGFloat = 0.9
}

/// Installs, replaces or removes the client certificate for one server. A native form sheet on
/// the Mac, a design system card sheet everywhere else.
public struct ClientCertificateSheet: View {
    @Bindable var store: StoreOf<ClientCertificateFeature>

    public init(store: StoreOf<ClientCertificateFeature>) {
        self.store = store
    }

    public var body: some View {
        content
            .interactiveDismissDisabled(store.isImporting)
            .onAppear { store.send(.onAppear) }
            .fileImporter(
                isPresented: $store.isFileImporterPresented.sending(\.fileImporterPresentationChanged),
                allowedContentTypes: [.pkcs12]
            ) { result in
                if case let .success(url) = result {
                    store.send(.filePicked(url))
                }
            }
            .dsAlert(isPresented: Binding(get: { store.isConfirmingRemoval }, set: { _ in })) {
                DSAlertSheet(
                    icon: IconKit.delete,
                    title: L10n.ClientCertificate.removeTitle,
                    message: L10n.ClientCertificate.removeMessage(store.serverName),
                    confirmTitle: L10n.ClientCertificate.removeConfirm,
                    dismissTitle: L10n.Common.cancel,
                    role: .destructive,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: { store.send(.removeConfirmed) },
                    onDismiss: { store.send(.removeCancelled) }
                )
            }
    }

    private var content: some View {
        #if os(macOS)
            ClientCertificateMacForm(store: store)
        #else
            phoneBody
        #endif
    }

    private var phoneBody: some View {
        DSDynamicHeightSheet(maxHeightFraction: Metrics.maxHeightFraction) {
            VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
                DSSheetHeader(
                    icon: IconKit.accessRules,
                    title: L10n.ClientCertificate.title,
                    closeAccessibilityLabel: L10n.Common.close,
                    onClose: { store.send(.closeTapped) }
                )

                Text(L10n.ClientCertificate.intro)
                    .type(.body3(.regular), style: .secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let failure = store.failure, store.pendingFile == nil || failure != .wrongPassword {
                    DSErrorCard(failure.message)
                }

                section(L10n.ClientCertificate.serverLabel) {
                    Text(store.serverName)
                        .type(.body2(.regular))
                        .dsCard()
                }

                section(L10n.ClientCertificate.certificateLabel) {
                    VStack(alignment: .leading, spacing: .space8) {
                        ClientCertificateSummaryLines(summary: store.installedSummary)
                        ClientCertificateExpiryWarning(summary: store.installedSummary)
                    }
                    .dsCard()
                }

                if let file = store.pendingFile {
                    section(L10n.ClientCertificate.fileLabel) {
                        Label {
                            Text(file.name).type(.body2(.regular)).lineLimit(1).truncationMode(.middle)
                        } icon: {
                            IconKit.document.foregroundStyle(Color.accentText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dsCard()
                    }
                    section(
                        L10n.ClientCertificate.passwordLabel,
                        error: store.failure == .wrongPassword ? store.failure?.message : nil
                    ) {
                        DSSecureField(
                            L10n.ClientCertificate.passwordLabel,
                            text: $store.passphrase.sending(\.passphraseChanged),
                            prompt: Text(L10n.ClientCertificate.passwordPrompt)
                        )
                        .submitLabel(.done)
                        .onSubmit { store.send(.installTapped) }
                    }
                }
            }
            .padding(.horizontal, Metrics.horizontalPadding)
            .padding(.vertical, Metrics.verticalPadding)
        } footer: {
            DSSheetFooter {
                VStack(spacing: Metrics.footerSpacing) {
                    footerButtons
                }
            }
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        if store.pendingFile != nil {
            DSButton(L10n.ClientCertificate.install, style: .primary, isLoading: store.isImporting) {
                store.send(.installTapped)
            }
            .disabled(!store.canInstall)
            DSButton(L10n.ClientCertificate.chooseAnother, style: .ghost) {
                store.send(.chooseFileTapped)
            }
            .disabled(store.isImporting)
        } else {
            DSButton(
                store.installedSummary == nil ? L10n.ClientCertificate.chooseFile : L10n.ClientCertificate.replace,
                style: .primary
            ) {
                store.send(.chooseFileTapped)
            }
            .disabled(store.status == .loading)
            if store.installedSummary != nil {
                DSButton(L10n.ClientCertificate.remove, style: .failure) {
                    store.send(.removeTapped)
                }
            }
        }
    }

    private func section(
        _ title: String,
        error: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            DSFieldLabel(title)
            content()
            if let error {
                Text(error).type(.body3(.semibold), style: .error)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension StoreOf<ClientCertificateFeature> {
    static func preview(_ state: ClientCertificateFeature.State) -> StoreOf<ClientCertificateFeature> {
        Store(initialState: state) {
            ClientCertificateFeature()
        } withDependencies: {
            $0.clientCertificateClient = .inMemory(
                state.installedSummary.map { [state.origin: $0] } ?? [:]
            )
        }
    }
}

extension ClientCertificateOrigin {
    static let preview = ClientCertificateOrigin(host: "files.example.com", port: 8443)
}

#Preview("Empty") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ClientCertificateSheet(store: .preview(.init(origin: .preview, status: .empty)))
    }
}

#Preview("Installed") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ClientCertificateSheet(store: .preview(.init(origin: .preview, status: .installed(.preview))))
    }
}

#Preview("Expired") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ClientCertificateSheet(store: .preview(.init(origin: .preview, status: .installed(.previewExpired))))
    }
}

#Preview("File picked") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ClientCertificateSheet(store: .preview(.init(
            origin: .preview,
            status: .empty,
            pendingFile: .init(name: "phillip-iphone.p12", data: Data())
        )))
    }
}

#Preview("Wrong password") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ClientCertificateSheet(store: .preview(.init(
            origin: .preview,
            status: .empty,
            pendingFile: .init(name: "phillip-iphone.p12", data: Data()),
            passphrase: "hunter2",
            importPhase: .failed(.wrongPassword)
        )))
    }
}

#Preview("Invalid file") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ClientCertificateSheet(store: .preview(.init(
            origin: .preview,
            status: .empty,
            importPhase: .failed(.invalidFile)
        )))
    }
}
