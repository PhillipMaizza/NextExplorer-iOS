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
            ShareUploadMacView(store: store)
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
                    if store.credentials != nil, store.canChooseAccount || [.checking, .ready, .preparing, .started].contains(store.phase) {
                        section(L10n.ShareUpload.accountLabel) {
                            ShareUploadAccountMenu(store: store)
                        }
                    }
                    if store.credentials != nil, [.checking, .ready, .preparing, .started].contains(store.phase) {
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

/// The account receiving the files: a menu of every signed in account when there are several.
struct ShareUploadAccountMenu: View {
    let store: StoreOf<ShareUploadFeature>

    var body: some View {
        if store.canChooseAccount {
            Menu {
                ForEach(store.accounts, id: \.accountID) { account in
                    Button {
                        store.send(.accountSelected(account.accountID))
                    } label: {
                        if account.accountID == store.credentials?.accountID {
                            Label {
                                Text(ShareUploadFeature.State.name(for: account))
                            } icon: {
                                IconKit.checkmark
                            }
                        } else {
                            Text(ShareUploadFeature.State.name(for: account))
                        }
                    }
                }
            } label: {
                HStack(spacing: .space8) {
                    Text(store.accountName).type(.body2(.regular)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    IconKit.chevronUpDown.foregroundStyle(Color.secondaryDS)
                }
                .dsCard()
            }
            .buttonStyle(DSHapticButtonStyle())
        } else {
            Text(store.accountName).type(.body2(.regular)).frame(maxWidth: .infinity, alignment: .leading).dsCard()
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

extension StoreOf<ShareUploadFeature> {
    static func preview(_ phase: ShareUploadFeature.Phase, destination: String = "Photos/2026", accounts: Int = 1) -> StoreOf<ShareUploadFeature> {
        var state = ShareUploadFeature.State()
        state.accounts = Array([SessionCredentials.preview, .previewSecond].prefix(accounts))
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
    static let previewSecond = SessionCredentials(
        serverBaseURL: URL(string: "https://home.example.org")!,
        authMode: .local,
        cookieName: "connect.sid",
        cookieValue: "preview",
        cookieDomain: "home.example.org",
        cookiePath: "/",
        cookieIsSecure: true,
        expiresAt: nil,
        username: "family"
    )

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
#Preview("Two accounts") { ShareUploadView(store: .preview(.ready, accounts: 2)) }
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

#Preview("Status, every phase") {
    VStack(alignment: .leading, spacing: .space16) {
        ForEach(
            [ShareUploadFeature.Phase.loading, .checking, .ready, .preparing, .started, .signedOut, .nothingToUpload, .failed, .certificateRequired, .certificateRejected],
            id: \.self
        ) { phase in
            ShareUploadStatus(store: .preview(phase))
        }
    }
    .padding(.space24)
}

#Preview("Account menu") {
    VStack(spacing: .space16) {
        ShareUploadAccountMenu(store: .preview(.ready, accounts: 2))
        ShareUploadAccountMenu(store: .preview(.ready))
    }
    .padding(.space24)
}

#Preview("Folder button") {
    VStack(spacing: .space16) {
        ShareUploadFolderButton(store: .preview(.ready))
        ShareUploadFolderButton(store: .preview(.ready, destination: ""))
        ShareUploadFolderButton(store: .preview(.preparing))
    }
    .padding(.space24)
}
