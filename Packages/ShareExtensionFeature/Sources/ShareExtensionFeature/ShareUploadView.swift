import ComposableArchitecture
import CoreModels
import Dependencies
import DesignSystem
import FolderPickerFeature
import Localization
import SwiftUI

private enum Metrics {
    static let contentSpacing: CGFloat = .space24
    static let sectionSpacing: CGFloat = .space8
    static let padding: CGFloat = .space24
    static let singleLine = 1
}

/// The Share Extension's screen. A design system card on iPhone and iPad, a native form on the Mac.
public struct ShareUploadView: View {
    @Bindable var store: StoreOf<ShareUploadFeature>
    @Dependency(\.openApp) private var openApp

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
                    if store.credentials != nil, store.canChooseAccount || store.shouldShowDetails {
                        section(L10n.ShareUpload.accountLabel) {
                            ShareUploadAccountMenu(store: store)
                        }
                    }
                    if store.credentials != nil, store.shouldShowDetails {
                        section(L10n.ShareUpload.folderLabel) {
                            ShareUploadFolderButton(store: store)
                        }
                    }
                }
                .padding(Metrics.padding)
            }
            if store.state.hasActions(canOpenApp: openApp.isAvailable) {
                DSSheetFooter {
                    ShareUploadActions(store: store)
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

/// The account receiving the files: a menu of every signed in account when there are several.
struct ShareUploadAccountMenu: View {
    let store: StoreOf<ShareUploadFeature>

    var body: some View {
        if store.canChooseAccount {
            Menu {
                Picker(L10n.ShareUpload.accountLabel, selection: Binding(
                    get: { store.credentials?.accountID ?? "" },
                    set: { store.send(.accountSelected($0)) }
                )) {
                    // Title and subtitle lines: a long server name no longer breaks mid word.
                    ForEach(store.accounts, id: \.accountID) { account in
                        VStack {
                            Text(account.username ?? account.serverBaseURL.host() ?? "")
                            Text(account.serverBaseURL.host() ?? "")
                        }
                        .tag(account.accountID)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: .space8) {
                    Text(store.accountName).type(.body2(.regular)).lineLimit(Metrics.singleLine).truncationMode(.middle)
                    Spacer()
                    IconKit.chevronUpDown.foregroundStyle(Color.secondaryDS)
                }
                .dsCard()
            }
            .buttonStyle(DSHapticButtonStyle())
            .accessibilityLabel(L10n.ShareUpload.accountLabel)
            .accessibilityValue(store.accountName)
            .accessibilityHint(L10n.ShareUpload.accountHint)
        } else {
            Text(store.accountName)
                .type(.body2(.regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsCard()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.ShareUpload.accountLabel)
                .accessibilityValue(store.accountName)
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
                    .lineLimit(Metrics.singleLine)
                    .truncationMode(.head)
                Spacer()
                IconKit.chevronRight.foregroundStyle(Color.secondaryDS)
            }
            .dsCard()
        }
        .buttonStyle(DSHapticButtonStyle())
        .disabled(store.phase != .ready)
        .accessibilityLabel(L10n.ShareUpload.folderLabel)
        .accessibilityValue(store.destination.isEmpty ? L10n.ShareUpload.folderChoose : store.destination)
        .accessibilityHint(L10n.ShareUpload.folderHint)
    }
}

extension StoreOf<ShareUploadFeature> {
    static func preview(
        _ phase: ShareUploadFeature.Phase,
        destination: String = "Photos/2026",
        accounts: Int = 1,
        notice: ShareUploadFeature.Notice? = nil,
        failures: [ItemFailure] = [],
        livePhotos: Int = 0
    ) -> StoreOf<ShareUploadFeature> {
        var state = ShareUploadFeature.State()
        state.accounts = Array([SessionCredentials.preview, .previewSecond].prefix(accounts))
        state.phase = phase
        state.itemCount = 12
        state.livePhotoCount = livePhotos
        state.preparingTotal = 12
        state.progress = PreparationProgress(completed: 4, fraction: 0.4)
        state.stagedCount = 9
        state.failures = phase == .failed || phase == .partiallyPrepared ? (failures.isEmpty ? ItemFailure.previews : failures) : []
        state.notice = notice
        state.destination = destination
        if phase != .signedOut, phase != .sessionUnreadable {
            state.credentials = .preview
        }
        return Store(initialState: state) { EmptyReducer() }
    }
}

private enum PreviewConstants {
    static let firstHost = "files.example.com"
    static let secondHost = "home.example.org"
    static let cookieName = "connect.sid"
    static let cookieValue = "preview"
    static let cookiePath = "/"
}

extension SessionCredentials {
    private static func previewAccount(host: String, username: String) -> SessionCredentials {
        SessionCredentials(
            serverBaseURL: URL(string: "https://\(host)") ?? URL(fileURLWithPath: PreviewConstants.cookiePath),
            authMode: .local,
            cookieName: PreviewConstants.cookieName,
            cookieValue: PreviewConstants.cookieValue,
            cookieDomain: host,
            cookiePath: PreviewConstants.cookiePath,
            cookieIsSecure: true,
            expiresAt: nil,
            username: username
        )
    }

    static let previewSecond = previewAccount(host: PreviewConstants.secondHost, username: "family")
    static let preview = previewAccount(host: PreviewConstants.firstHost, username: "phillip")
}

#Preview("Ready") { ShareUploadView(store: .preview(.ready)) }
#Preview("Two accounts") { ShareUploadView(store: .preview(.ready, accounts: 2)) }
#Preview("No folder yet") { ShareUploadView(store: .preview(.ready, destination: "")) }
#Preview("Preparing") { ShareUploadView(store: .preview(.preparing)) }
#Preview("Handing off") { ShareUploadView(store: .preview(.handingOff)) }
#Preview("Started") { ShareUploadView(store: .preview(.started)) }
#Preview("Loading") { ShareUploadView(store: .preview(.loading)) }
#Preview("Checking the server") { ShareUploadView(store: .preview(.checking)) }
#Preview("Partly prepared") { ShareUploadView(store: .preview(.partiallyPrepared)) }
#Preview("Signed out") { ShareUploadView(store: .preview(.signedOut)) }
#Preview("Session unreadable") { ShareUploadView(store: .preview(.sessionUnreadable)) }
#Preview("Nothing to upload") { ShareUploadView(store: .preview(.nothingToUpload)) }
#Preview("Failed") { ShareUploadView(store: .preview(.failed)) }
#Preview("Certificate required") { ShareUploadView(store: .preview(.certificateRequired)) }
#Preview("Certificate refused") { ShareUploadView(store: .preview(.certificateRejected)) }
#Preview("Default folder gone") { ShareUploadView(store: .preview(.ready, destination: "", notice: .defaultFolderUnavailable)) }

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
