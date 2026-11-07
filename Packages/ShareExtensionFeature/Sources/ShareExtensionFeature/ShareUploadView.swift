import ComposableArchitecture
import CoreModels
import DesignSystem
import FolderPickerFeature
import Localization
import SwiftUI

private enum Metrics {
    static let contentSpacing: CGFloat = .space24
    static let sectionSpacing: CGFloat = .space8
    static let padding: CGFloat = .space24
}

/// The Share Extension's screen. A design system card on iPhone and iPad, a native form on the Mac.
public struct ShareUploadView: View {
    @Bindable var store: StoreOf<ShareUploadFeature>

    public init(store: StoreOf<ShareUploadFeature>) {
        self.store = store
    }

    public var body: some View {
        content
            .onAppear { store.send(.onAppear) }
            .sheet(item: $store.scope(state: \.folderPicker, action: \.folderPicker)) { pickerStore in
                DestinationPickerView(store: pickerStore)
            }
    }

    private var content: some View {
        #if os(macOS)
            ShareUploadMacForm(store: store)
        #else
            phoneBody
        #endif
    }

    private var phoneBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
                    DSSheetHeader(
                        icon: IconKit.upload,
                        title: L10n.ShareUpload.title,
                        closeAccessibilityLabel: L10n.Common.close,
                        onClose: { store.send(.cancelTapped) }
                    )
                    ShareUploadStatus(store: store)
                    if store.credentials != nil, [.checking, .ready, .preparing, .started].contains(store.phase) {
                        section(L10n.ShareUpload.accountLabel) {
                            Text(store.accountName).type(.body2(.regular)).dsCard()
                        }
                        section(L10n.ShareUpload.folderLabel) {
                            ShareUploadFolderButton(store: store)
                        }
                    }
                }
                .padding(Metrics.padding)
            }
            if [.checking, .ready, .preparing].contains(store.phase) {
                DSSheetFooter {
                    DSButton(L10n.ShareUpload.upload, style: .primary, isLoading: store.phase == .preparing) {
                        store.send(.uploadTapped)
                    }
                    .disabled(!store.canUpload)
                }
            }
        }
        .background(Color.backgroundPrimary)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            DSFieldLabel(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The line under the title: how many files, or why nothing can be uploaded.
struct ShareUploadStatus: View {
    let store: StoreOf<ShareUploadFeature>

    var body: some View {
        switch store.phase {
        case .loading:
            DSSpinner().frame(maxWidth: .infinity)
        case .signedOut:
            DSErrorCard(L10n.ShareUpload.signedOut)
        case .nothingToUpload:
            DSErrorCard(L10n.ShareUpload.nothingToUpload)
        case .failed:
            DSErrorCard(L10n.ShareUpload.failed)
        case .certificateRequired:
            DSErrorCard(L10n.Error.clientCertificateRequired)
        case .certificateRejected:
            DSErrorCard(L10n.Error.clientCertificateRejected)
        case .checking, .ready:
            Text(L10n.ShareUpload.itemCount(store.itemCount)).type(.body2(.regular), style: .secondary)
        case .preparing:
            Text(L10n.ShareUpload.preparing(min(store.preparedCount + 1, store.itemCount), store.itemCount))
                .type(.body2(.regular), style: .secondary)
        case .started:
            Label {
                Text(L10n.ShareUpload.started).type(.body2(.regular))
            } icon: {
                IconKit.checkmark.foregroundStyle(Color.positiveText)
            }
        }
    }
}

/// The chosen folder, tapping it opens the folder picker.
struct ShareUploadFolderButton: View {
    let store: StoreOf<ShareUploadFeature>

    var body: some View {
        Button {
            store.send(.chooseFolderTapped)
        } label: {
            HStack(spacing: .space8) {
                IconKit.folderFill.foregroundStyle(Color.accentText)
                Text(store.destination.isEmpty ? L10n.ShareUpload.folderChoose : store.destination)
                    .type(.body2(.regular), style: store.destination.isEmpty ? .secondary : .primaryOnSurface)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                IconKit.chevronRight.foregroundStyle(Color.secondaryDS)
            }
            .dsCard()
        }
        .buttonStyle(DSHapticButtonStyle())
        .disabled(store.phase != .ready)
    }
}

#if os(macOS)
    /// The Mac's form: the same rows as the phone card, Return uploads, Esc closes.
    struct ShareUploadMacForm: View {
        let store: StoreOf<ShareUploadFeature>

        var body: some View {
            MacFormSheet(
                title: L10n.ShareUpload.title,
                message: message,
                confirmTitle: L10n.ShareUpload.upload,
                isConfirmEnabled: store.canUpload,
                isWorking: store.phase == .preparing,
                errorMessage: errorMessage,
                cancelTitle: store.phase == .started ? L10n.Common.close : L10n.Common.cancel,
                onCancel: { store.send(.cancelTapped) },
                onConfirm: { store.send(.uploadTapped) }
            ) {
                if store.credentials != nil, store.phase != .signedOut {
                    LabeledContent(L10n.ShareUpload.accountLabel) { Text(store.accountName) }
                        .padding(.bottom, .space12)
                    LabeledContent(L10n.ShareUpload.folderLabel) {
                        HStack {
                            Text(store.destination.isEmpty ? "" : store.destination).lineLimit(1).truncationMode(.head)
                            Button(L10n.ShareUpload.folderChoose) { store.send(.chooseFolderTapped) }
                                .disabled(store.phase != .ready)
                        }
                    }
                }
            }
        }

        private var message: String? {
            switch store.phase {
            case .checking, .ready: L10n.ShareUpload.itemCount(store.itemCount)
            case .preparing: L10n.ShareUpload.preparing(min(store.preparedCount + 1, store.itemCount), store.itemCount)
            case .started: L10n.ShareUpload.started
            case .loading, .signedOut, .nothingToUpload, .failed, .certificateRequired, .certificateRejected: nil
            }
        }

        private var errorMessage: String? {
            switch store.phase {
            case .signedOut: L10n.ShareUpload.signedOut
            case .nothingToUpload: L10n.ShareUpload.nothingToUpload
            case .failed: L10n.ShareUpload.failed
            case .certificateRequired: L10n.Error.clientCertificateRequired
            case .certificateRejected: L10n.Error.clientCertificateRejected
            case .loading, .checking, .ready, .preparing, .started: nil
            }
        }
    }
#endif

extension StoreOf<ShareUploadFeature> {
    static func preview(_ phase: ShareUploadFeature.Phase, destination: String = "Photos/2026") -> StoreOf<ShareUploadFeature> {
        var state = ShareUploadFeature.State()
        state.phase = phase
        state.itemCount = 12
        state.preparedCount = 4
        state.destination = destination
        if phase != .signedOut {
            state.credentials = .preview
        }
        return Store(initialState: state) { EmptyReducer() }
    }
}

extension SessionCredentials {
    static let preview = SessionCredentials(
        serverBaseURL: URL(string: "https://files.example.com")!,
        authMode: .local,
        cookieName: "connect.sid",
        cookieValue: "preview",
        cookieDomain: "files.example.com",
        cookiePath: "/",
        cookieIsSecure: true,
        expiresAt: nil,
        username: "phillip"
    )
}

#Preview("Ready") { ShareUploadView(store: .preview(.ready)) }
#Preview("No folder yet") { ShareUploadView(store: .preview(.ready, destination: "")) }
#Preview("Preparing") { ShareUploadView(store: .preview(.preparing)) }
#Preview("Started") { ShareUploadView(store: .preview(.started)) }
#Preview("Loading") { ShareUploadView(store: .preview(.loading)) }
#Preview("Checking the server") { ShareUploadView(store: .preview(.checking)) }
#Preview("Signed out") { ShareUploadView(store: .preview(.signedOut)) }
#Preview("Nothing to upload") { ShareUploadView(store: .preview(.nothingToUpload)) }
#Preview("Failed") { ShareUploadView(store: .preview(.failed)) }
#Preview("Certificate required") { ShareUploadView(store: .preview(.certificateRequired)) }
#Preview("Certificate refused") { ShareUploadView(store: .preview(.certificateRejected)) }
