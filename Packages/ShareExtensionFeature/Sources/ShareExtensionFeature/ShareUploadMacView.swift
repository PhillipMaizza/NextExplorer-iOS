#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import Dependencies
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 460
        static let singleLine = 1
        static let failureLineLimit = 2
        static let minHeight: CGFloat = 240
        static let failureListMaxHeight: CGFloat = 96
        static let logoSize: CGFloat = .size40
        static let iconWidth: CGFloat = .size20
        static let rowPadding: CGFloat = .space12
        static let noticePadding: CGFloat = .space12
        static let noticeOpacity: Double = 0.12
        static let borderOpacity: Double = 0.5
    }

    /// The Mac share sheet: the app mark and what is being sent, the account and folder in one
    /// grouped box, any problem as a tinted notice, then Cancel (Esc) and Upload (Return). It is
    /// as tall as its content needs, so a long notice in German or Russian, or two accounts, never
    /// clips.
    struct ShareUploadMacView: View {
        let store: StoreOf<ShareUploadFeature>
        @Dependency(\.openApp) private var openApp

        var body: some View {
            VStack(alignment: .leading, spacing: .space16) {
                header
                if store.credentials != nil, store.canChooseAccount || store.shouldShowDetails {
                    details
                }
                if let notice {
                    ShareUploadMacNotice(notice: notice)
                }
                if store.phase == .preparing || store.phase == .handingOff {
                    preparingProgress
                }
                if !store.failures.isEmpty, store.phase == .partiallyPrepared || store.phase == .failed {
                    failureList
                }
                buttons
            }
            .padding(.space24)
            .frame(width: Metrics.width)
            .frame(minHeight: Metrics.minHeight, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
        }

        private var buttons: some View {
            let primary = store.state.primaryAction(canOpenApp: openApp.isAvailable)
            let secondary = store.state.secondaryAction(canOpenApp: openApp.isAvailable)
            return MacDialogButtons(
                confirmTitle: primary?.title,
                isConfirmEnabled: primary != .upload || store.canUpload,
                isWorking: store.isWorking,
                cancelTitle: store.phase == .started ? L10n.Common.close : L10n.Common.cancel,
                secondaryTitle: secondary?.title,
                onSecondary: {
                    if let secondary {
                        store.send(secondary.action)
                    }
                },
                onCancel: { store.send(.cancelTapped) },
                onConfirm: {
                    if let primary {
                        store.send(primary.action)
                    }
                }
            )
        }

        private var header: some View {
            HStack(spacing: .space12) {
                DSLogoMark(size: Metrics.logoSize)
                VStack(alignment: .leading, spacing: .space2) {
                    Text(L10n.ShareUpload.title).font(.title3.weight(.semibold))
                    if let subtitle {
                        Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if store.livePhotoCount > 0, store.phase == .ready || store.phase == .checking {
                        Text(L10n.ShareUpload.livePhotoNote).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }

        private var subtitle: String? {
            switch store.phase {
            case .ready: L10n.ShareUpload.itemCount(store.itemCount)
            case .checking: L10n.ShareUpload.checking(store.serverName)
            case .preparing, .handingOff: L10n.ShareUpload.preparing(store.preparingStep, store.preparingTotal)
            case .partiallyPrepared: L10n.ShareUpload.readyCount(store.stagedCount)
            case .loading, .started, .signedOut, .sessionUnreadable, .nothingToUpload, .failed, .certificateRequired, .certificateRejected: nil
            }
        }

        private var preparingProgress: some View {
            VStack(alignment: .leading, spacing: .space4) {
                ProgressView(value: store.preparationFraction)
                Text(L10n.ShareUpload.keepOpen).font(.callout).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }

        private var failureList: some View {
            VStack(alignment: .leading, spacing: .space4) {
                Text(L10n.ShareUpload.failedItemsHeader).font(.callout.weight(.semibold))
                ScrollView {
                    VStack(alignment: .leading, spacing: .space4) {
                        ForEach(store.failures) { failure in
                            Text(failure.line)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(Metrics.failureLineLimit)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: Metrics.failureListMaxHeight)
            }
            .accessibilityElement(children: .contain)
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
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityLabel(L10n.ShareUpload.accountLabel)
                        .accessibilityValue(store.accountName)
                        .accessibilityHint(L10n.ShareUpload.accountHint)
                        .help(store.accountName)
                    } else {
                        Text(store.accountName)
                            .lineLimit(Metrics.singleLine)
                            .truncationMode(.middle)
                            .help(store.accountName)
                            .accessibilityLabel(L10n.ShareUpload.accountLabel)
                            .accessibilityValue(store.accountName)
                    }
                }
                if store.shouldShowDetails {
                    Divider().padding(.leading, Metrics.rowPadding + Metrics.iconWidth + .space8)
                    ShareUploadMacRow(icon: IconKit.folderFill, label: L10n.ShareUpload.folderLabel) {
                        HStack(spacing: .space8) {
                            if !store.destination.isEmpty {
                                Text(store.destination)
                                    .lineLimit(Metrics.singleLine)
                                    .truncationMode(.middle)
                                    .help(store.destination)
                            }
                            Button(store.destination.isEmpty ? L10n.ShareUpload.folderChoose : L10n.Common.change) {
                                store.send(.chooseFolderTapped)
                            }
                            .disabled(store.phase != .ready)
                            .accessibilityLabel(L10n.ShareUpload.folderLabel)
                            .accessibilityValue(store.destination.isEmpty ? L10n.ShareUpload.folderChoose : store.destination)
                            .accessibilityHint(L10n.ShareUpload.folderHint)
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
            case .sessionUnreadable: .problem(L10n.ShareUpload.sessionUnreadable)
            case .nothingToUpload: .problem(L10n.ShareUpload.nothingToUpload)
            case .failed: .problem(L10n.ShareUpload.failed)
            case .certificateRequired: .problem(L10n.ShareUpload.certificateRequired)
            case .certificateRejected: .problem(L10n.ShareUpload.certificateRejected)
            case .ready where store.notice == .defaultFolderUnavailable: .problem(L10n.ShareUpload.defaultFolderUnavailable)
            case .loading, .checking, .ready, .preparing, .handingOff, .partiallyPrepared: nil
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
                Text(label).foregroundStyle(.secondary).fixedSize()
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
    #Preview("Live Photos") { ShareUploadMacView(store: .preview(.ready, livePhotos: 3)) }
    #Preview("Long folder path") {
        ShareUploadMacView(store: .preview(.ready, destination: "Photos/Family/2026/Summer holiday in the mountains/Day three"))
    }

    #Preview("Default folder gone") { ShareUploadMacView(store: .preview(.ready, destination: "", notice: .defaultFolderUnavailable)) }
    #Preview("Checking") { ShareUploadMacView(store: .preview(.checking)) }
    #Preview("Preparing") { ShareUploadMacView(store: .preview(.preparing)) }
    #Preview("Handing off") { ShareUploadMacView(store: .preview(.handingOff)) }
    #Preview("Partly prepared") { ShareUploadMacView(store: .preview(.partiallyPrepared)) }
    #Preview("Failed") { ShareUploadMacView(store: .preview(.failed)) }
    #Preview("Started") { ShareUploadMacView(store: .preview(.started)) }
    #Preview("Signed out") { ShareUploadMacView(store: .preview(.signedOut)) }
    #Preview("Session unreadable") { ShareUploadMacView(store: .preview(.sessionUnreadable)) }
    #Preview("Nothing to upload") { ShareUploadMacView(store: .preview(.nothingToUpload)) }
    #Preview("Certificate required") { ShareUploadMacView(store: .preview(.certificateRequired)) }
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
