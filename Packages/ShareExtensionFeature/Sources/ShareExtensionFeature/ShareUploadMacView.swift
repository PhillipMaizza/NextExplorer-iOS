#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 460
        static let logoSize: CGFloat = .size40
        static let iconWidth: CGFloat = .size20
        static let rowPadding: CGFloat = .space12
        static let noticePadding: CGFloat = .space12
        static let noticeOpacity: Double = 0.12
        static let borderOpacity: Double = 0.5
    }

    /// The Mac share sheet: the app mark and what is being sent, the account and folder in one
    /// grouped box, any problem as a tinted notice, then Cancel (Esc) and Upload (Return).
    struct ShareUploadMacView: View {
        let store: StoreOf<ShareUploadFeature>

        var body: some View {
            VStack(alignment: .leading, spacing: .space16) {
                header
                if store.credentials != nil, store.canChooseAccount || [.checking, .ready, .preparing, .started].contains(store.phase) {
                    details
                }
                Spacer(minLength: 0)
                if let notice {
                    ShareUploadMacNotice(notice: notice)
                }
                MacDialogButtons(
                    confirmTitle: L10n.ShareUpload.upload,
                    isConfirmEnabled: store.canUpload,
                    isWorking: store.phase == .preparing || store.phase == .checking,
                    cancelTitle: store.phase == .started ? L10n.Common.close : L10n.Common.cancel,
                    onCancel: { store.send(.cancelTapped) },
                    onConfirm: { store.send(.uploadTapped) }
                )
            }
            .padding(.space24)
            .frame(width: Metrics.width)
            .frame(maxHeight: .infinity, alignment: .top)
        }

        private var header: some View {
            HStack(spacing: .space12) {
                DSLogoMark(size: Metrics.logoSize)
                VStack(alignment: .leading, spacing: .space2) {
                    Text(L10n.ShareUpload.title).font(.title3.weight(.semibold))
                    if let subtitle {
                        Text(subtitle).foregroundStyle(.secondary)
                    }
                }
            }
        }

        private var subtitle: String? {
            switch store.phase {
            case .checking, .ready: L10n.ShareUpload.itemCount(store.itemCount)
            case .preparing: L10n.ShareUpload.preparing(min(store.preparedCount + 1, store.itemCount), store.itemCount)
            case .loading, .started, .signedOut, .nothingToUpload, .failed, .certificateRequired, .certificateRejected: nil
            }
        }

        private var details: some View {
            VStack(spacing: 0) {
                ShareUploadMacRow(icon: IconKit.account, label: L10n.ShareUpload.accountLabel) {
                    if store.canChooseAccount {
                        Picker(L10n.ShareUpload.accountLabel, selection: Binding(
                            get: { store.credentials?.accountID ?? "" },
                            set: { store.send(.accountSelected($0)) }
                        )) {
                            ForEach(store.accounts, id: \.accountID) { account in
                                Text(ShareUploadFeature.State.name(for: account)).tag(account.accountID)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    } else {
                        Text(store.accountName).lineLimit(1).truncationMode(.middle)
                    }
                }
                if [.checking, .ready, .preparing, .started].contains(store.phase) {
                    Divider().padding(.leading, Metrics.rowPadding + Metrics.iconWidth + .space8)
                    ShareUploadMacRow(icon: IconKit.folderFill, label: L10n.ShareUpload.folderLabel) {
                        HStack(spacing: .space8) {
                            if !store.destination.isEmpty {
                                Text(store.destination).lineLimit(1).truncationMode(.head)
                            }
                            Button(store.destination.isEmpty ? L10n.ShareUpload.folderChoose : L10n.Common.change) {
                                store.send(.chooseFolderTapped)
                            }
                            .disabled(store.phase != .ready)
                        }
                    }
                }
            }
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: .radiusMedium))
            .overlay(RoundedRectangle(cornerRadius: .radiusMedium).strokeBorder(Color.borderPrimary.opacity(Metrics.borderOpacity)))
        }

        private var notice: ShareUploadMacNotice.Notice? {
            switch store.phase {
            case .started: .done(L10n.ShareUpload.started)
            case .signedOut: .problem(L10n.ShareUpload.signedOut)
            case .nothingToUpload: .problem(L10n.ShareUpload.nothingToUpload)
            case .failed: .problem(L10n.ShareUpload.failed)
            case .certificateRequired: .problem(L10n.Error.clientCertificateRequired)
            case .certificateRejected: .problem(L10n.Error.clientCertificateRejected)
            case .loading, .checking, .ready, .preparing: nil
            }
        }
    }

    /// One labeled line of the grouped box: icon, label, then the value and its controls.
    struct ShareUploadMacRow<Value: View>: View {
        let icon: Image
        let label: String
        @ViewBuilder let value: () -> Value

        var body: some View {
            HStack(spacing: .space8) {
                icon
                    .foregroundStyle(Color.accentText)
                    .frame(width: Metrics.iconWidth)
                Text(label).foregroundStyle(.secondary)
                Spacer(minLength: .space16)
                value()
            }
            .padding(Metrics.rowPadding)
        }
    }

    /// The outcome or the reason nothing can be sent, tinted green or red.
    struct ShareUploadMacNotice: View {
        enum Notice: Equatable {
            case done(String)
            case problem(String)
        }

        let notice: Notice

        private var text: String {
            switch notice {
            case let .done(text), let .problem(text): text
            }
        }

        private var isProblem: Bool {
            if case .problem = notice {
                return true
            }
            return false
        }

        var body: some View {
            Label {
                Text(text).fixedSize(horizontal: false, vertical: true)
            } icon: {
                isProblem ? IconKit.warning : IconKit.checkmark
            }
            .foregroundStyle(isProblem ? Color.negativeText : Color.positiveText)
            .padding(Metrics.noticePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (isProblem ? Color.negativeText : Color.positiveText).opacity(Metrics.noticeOpacity),
                in: RoundedRectangle(cornerRadius: .radiusMedium)
            )
        }
    }

    #Preview("Ready") { ShareUploadMacView(store: .preview(.ready)) }
    #Preview("Two accounts") { ShareUploadMacView(store: .preview(.ready, accounts: 2)) }
    #Preview("No folder yet") { ShareUploadMacView(store: .preview(.ready, destination: "")) }
    #Preview("Checking") { ShareUploadMacView(store: .preview(.checking)) }
    #Preview("Preparing") { ShareUploadMacView(store: .preview(.preparing)) }
    #Preview("Started") { ShareUploadMacView(store: .preview(.started)) }
    #Preview("Signed out") { ShareUploadMacView(store: .preview(.signedOut)) }
    #Preview("Certificate refused") { ShareUploadMacView(store: .preview(.certificateRejected)) }
    #Preview("Row") {
        ShareUploadMacRow(icon: IconKit.folderFill, label: "Folder") { Text("Photos/2026") }
            .frame(width: 420)
    }

    #Preview("Notices") {
        VStack {
            ShareUploadMacNotice(notice: .done("Uploading in the background."))
            ShareUploadMacNotice(notice: .problem("The server refused your client certificate."))
        }
        .padding()
        .frame(width: 420)
    }
#endif
