#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 540
        static let copyFeedbackSeconds: Double = 2
    }

    /// Create Share Link as a native Mac dialog: the form, then the created link with copy and
    /// share buttons.
    struct MacCreateShareLinkSheet: View {
        @Bindable var store: StoreOf<CreateShareLinkFeature>
        var onViewShares: (() -> Void)?
        @Environment(\.dismiss) private var dismiss
        @State private var copied: URL?

        var body: some View {
            Group {
                if let created = store.createdShare {
                    createdSheet(created)
                } else {
                    formSheet
                }
            }
            .task { store.send(.onAppear) }
        }

        private var formSheet: some View {
            MacFormSheet(
                title: L10n.CreateShare.title,
                confirmTitle: L10n.CreateShare.submit,
                isConfirmEnabled: store.isCreateEnabled,
                isWorking: store.isCreating,
                errorMessage: store.errorMessage ?? store.usersPhase.errorMessage,
                width: Metrics.width,
                onCancel: { dismiss() },
                onConfirm: { store.send(.createTapped) }
            ) {
                MacShareFormFields(
                    itemName: store.itemName,
                    sourcePath: store.sourcePath,
                    label: $store.label.sending(\.labelChanged),
                    accessMode: $store.accessMode.sending(\.accessModeChanged),
                    target: $store.target.sending(\.targetChanged),
                    users: Array(store.shareableUsers),
                    selectedUserIDs: store.selectedUserIDs,
                    usersPhase: store.usersPhase,
                    onToggleUser: { store.send(.userToggled($0)) },
                    isPasswordOn: $store.isPasswordEnabled.sending(\.passwordEnabledChanged),
                    password: $store.password.sending(\.passwordChanged),
                    passwordPrompt: L10n.Common.password,
                    isExpiryOn: $store.isExpiryEnabled.sending(\.expiryEnabledChanged),
                    expiresAt: $store.expiresAt.sending(\.expiresAtChanged)
                )
            }
        }

        private func createdSheet(_ created: CreatedShare) -> some View {
            let directLink = store.directLink ?? created.directFileUrl
            return MacFormSheet(
                title: L10n.CreateShare.titleCreated,
                confirmTitle: L10n.Common.done,
                cancelTitle: nil,
                secondaryTitle: onViewShares == nil ? nil : L10n.CreateShare.viewInShared,
                onSecondary: {
                    dismiss()
                    onViewShares?()
                },
                width: Metrics.width,
                onCancel: { dismiss() },
                onConfirm: { dismiss() }
            ) {
                Text(L10n.CreateShare.createdBanner).foregroundStyle(Color.positiveText)
                    .padding(.bottom, .space8)
                MacSettingsRow(L10n.CreateShare.sectionShareLink) {
                    linkRow(created.shareUrl)
                }
                MacSettingsRow(created.share.isDirectory ? L10n.CreateShare.directFolderLink : L10n.CreateShare.directFileLink) {
                    Picker(L10n.CreateShare.directLinkMode, selection: $store.directLinkMode.sending(\.directLinkModeChanged)) {
                        ForEach(DirectLinkMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    linkRow(directLink)
                }
                MacSettingsRow(L10n.CreateShare.summaryAccess) {
                    Text(created.share.accessMode.title)
                }
                MacSettingsRow(L10n.CreateShare.summarySharedWith) {
                    Text(created.share.sharingType == .anyone ? L10n.Shared.anyoneWithLink : recipientNames)
                }
                if created.share.hasPassword {
                    MacSettingsRow(L10n.Common.password) { Text(L10n.CreateShare.summaryPasswordProtected) }
                }
                if let expiresAt = created.share.expiresAt {
                    MacSettingsRow(L10n.CreateShare.summaryExpires) {
                        Text(expiresAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
        }

        /// The link itself, selectable, with Copy and the system share menu (AirDrop, Messages,
        /// Mail) beside it.
        private func linkRow(_ url: URL) -> some View {
            HStack(spacing: .space8) {
                Text(url.absoluteString)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(copied == url ? L10n.Common.copied : L10n.Common.copy) { copy(url) }
                ShareLink(item: url) { IconKit.share }
                    .accessibilityLabel(L10n.Common.share)
            }
        }

        private var recipientNames: String {
            let names = store.shareableUsers
                .filter { store.selectedUserIDs.contains($0.id) }
                .map { $0.displayName ?? $0.username }
            return names.isEmpty ? L10n.CreateShare.summarySpecificPeople : names.joined(separator: ", ")
        }

        private func copy(_ url: URL) {
            PlatformPasteboard.copy(url.absoluteString)
            copied = url
            Task {
                try? await Task.sleep(for: .seconds(Metrics.copyFeedbackSeconds))
                if copied == url {
                    copied = nil
                }
            }
        }
    }

    /// Edit Share as a native Mac dialog. The password can only be kept, changed or removed,
    /// since its current value can't be read back.
    struct MacEditShareSheet: View {
        @Bindable var store: StoreOf<EditShareFeature>
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            MacFormSheet(
                title: L10n.EditShare.title,
                confirmTitle: L10n.EditShare.save,
                isConfirmEnabled: store.isSaveEnabled,
                isWorking: store.isSaving,
                errorMessage: store.errorMessage ?? store.usersPhase.errorMessage,
                width: Metrics.width,
                onCancel: { dismiss() },
                onConfirm: { store.send(.saveTapped) }
            ) {
                MacShareFormFields(
                    itemName: store.share.displayName,
                    sourcePath: store.share.sourcePath,
                    label: $store.label.sending(\.labelChanged),
                    accessMode: $store.accessMode.sending(\.accessModeChanged),
                    target: $store.target.sending(\.targetChanged),
                    users: Array(store.shareableUsers),
                    selectedUserIDs: store.selectedUserIDs,
                    usersPhase: store.usersPhase,
                    onToggleUser: { store.send(.userToggled($0)) },
                    isPasswordOn: $store.wantsPassword.sending(\.wantsPasswordChanged),
                    password: $store.newPassword.sending(\.newPasswordChanged),
                    passwordPrompt: store.share.hasPassword ? L10n.EditShare.passwordKeepHint : L10n.Common.password,
                    isExpiryOn: $store.isExpiryEnabled.sending(\.expiryEnabledChanged),
                    expiresAt: $store.expiresAt.sending(\.expiresAtChanged)
                )
            }
        }
    }

    #Preview("Create") {
        MacCreateShareLinkSheet(store: Store(initialState: CreateShareLinkFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            itemName: "Electricity",
            itemPath: "Documents/Bills",
            isDirectory: true
        )) { CreateShareLinkFeature() } withDependencies: { $0.filesClient = .previewValue })
    }

    #Preview("Edit") {
        MacEditShareSheet(store: Store(initialState: EditShareFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            share: .previewCard(hasPassword: true, expiresAt: Date().addingTimeInterval(86_400 * 7))
        )) { EditShareFeature() } withDependencies: { $0.filesClient = .previewValue })
    }
#endif
