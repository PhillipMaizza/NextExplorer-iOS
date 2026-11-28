#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    /// Create Share Link as a native Mac dialog: the form, then the created link with copy and
    /// share buttons.
    struct MacCreateShareLinkSheet: View {
        @Bindable var store: StoreOf<CreateShareLinkFeature>
        var onViewShares: (() -> Void)?
        @Environment(\.dismiss) private var dismiss

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
                width: MacShareFormMetrics.sheetWidth,
                layout: .stacked,
                onCancel: { dismiss() },
                onConfirm: { store.send(.createTapped) }
            ) {
                MacShareFormFields(
                    itemName: store.itemName,
                    isDirectory: store.isDirectory,
                    location: store.itemPath,
                    label: $store.label.sending(\.labelChanged),
                    accessChoice: $store.accessChoice.sending(\.accessChoiceChanged),
                    permissions: $store.permissions.sending(\.permissionsChanged),
                    target: $store.target.sending(\.targetChanged),
                    users: Array(store.shareableUsers),
                    selectedUserIDs: store.selectedUserIDs,
                    usersPhase: store.usersPhase,
                    onToggleUser: { store.send(.userToggled($0)) },
                    isPasswordOn: $store.isPasswordEnabled.sending(\.passwordEnabledChanged),
                    password: $store.password.sending(\.passwordChanged),
                    passwordPrompt: L10n.Common.password,
                    isExpiryOn: $store.isExpiryEnabled.sending(\.expiryEnabledChanged),
                    expiresAt: $store.expiresAt.sending(\.expiresAtChanged),
                    isWritable: store.isWritable
                )
            }
        }

        private func createdSheet(_ created: CreatedShare) -> some View {
            let directLink = store.directLink ?? created.directFileUrl
            let shareLink = store.shareLink ?? created.shareUrl
            return MacFormSheet(
                title: L10n.CreateShare.titleCreated,
                confirmTitle: L10n.Common.done,
                cancelTitle: nil,
                secondaryTitle: onViewShares == nil ? nil : L10n.CreateShare.viewInShared,
                onSecondary: {
                    dismiss()
                    onViewShares?()
                },
                layout: .stacked,
                isSuccess: true,
                onCancel: { dismiss() },
                onConfirm: { dismiss() }
            ) {
                HStack(spacing: .space8) {
                    MacCopyBox(shareLink.absoluteString, icon: IconKit.link, isProminent: true)
                    ShareLink(item: shareLink) { IconKit.share }
                        .buttonStyle(.macDS(.secondary))
                        .accessibilityLabel(L10n.Common.share)
                }
                MacShareSettingsChips(share: created.share)
                MacLabeledField(L10n.CreateShare.summarySharedWith) {
                    MacShareAudienceRow(target: created.share.sharingType, recipients: recipients)
                }
                if !created.share.directLinkChoices.isEmpty {
                    MacLabeledField(created.share.isDirectory
                        ? L10n.CreateShare.directFolderLink
                        : L10n.CreateShare.directFileLink)
                    {
                        MacShareDirectLinkRow(
                            share: created.share,
                            link: directLink,
                            mode: $store.directLinkMode.sending(\.directLinkModeChanged)
                        )
                    }
                }
            }
        }

        private var recipients: [User] {
            store.shareableUsers.filter { store.selectedUserIDs.contains($0.id) }
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
                errorMessage: store.fieldError?.message ?? store.errorMessage ?? store.usersPhase.errorMessage,
                width: MacShareFormMetrics.sheetWidth,
                layout: .stacked,
                onCancel: { dismiss() },
                onConfirm: { store.send(.saveTapped) }
            ) {
                MacShareFormFields(
                    itemName: store.share.itemName,
                    isDirectory: store.share.isDirectory,
                    location: store.share.itemLocation,
                    label: $store.label.sending(\.labelChanged),
                    accessChoice: $store.accessChoice.sending(\.accessChoiceChanged),
                    permissions: $store.permissions.sending(\.permissionsChanged),
                    target: $store.target.sending(\.targetChanged),
                    users: Array(store.shareableUsers),
                    selectedUserIDs: store.selectedUserIDs,
                    usersPhase: store.usersPhase,
                    onToggleUser: { store.send(.userToggled($0)) },
                    isPasswordOn: $store.isPasswordEnabled.sending(\.wantsPasswordChanged),
                    password: $store.newPassword.sending(\.newPasswordChanged),
                    passwordPrompt: store.share.hasPassword ? L10n.EditShare.passwordKeepHint : L10n.Common.password,
                    isExpiryOn: $store.isExpiryEnabled.sending(\.expiryEnabledChanged),
                    expiresAt: $store.expiresAt.sending(\.expiresAtChanged)
                ) {
                    MacCopyBox(store.share.shareLink(serverURL: store.serverURL), icon: IconKit.link)
                }
            }
            .task { store.send(.task) }
        }
    }

    #Preview("Create") {
        MacCreateShareLinkSheet(store: Store(initialState: CreateShareLinkFeature.State(
            serverURL: sharedPreviewServerURL,
            itemName: "Electricity",
            itemPath: "Documents/Bills",
            isDirectory: true,
            now: .now
        )) { CreateShareLinkFeature() } withDependencies: { $0.filesClient = .previewValue })
    }

    #Preview("Created") {
        var state = CreateShareLinkFeature.State(
            serverURL: sharedPreviewServerURL,
            itemName: "Electricity",
            itemPath: "Documents/Bills",
            isDirectory: true,
            now: .now
        )
        let link = sharedPreviewServerURL.appending(path: "share/toks5")
        state.step = .created(CreatedShare(
            share: .previewCard(hasPassword: true, expiresAt: Date().addingTimeInterval(86_400 * 7)),
            shareUrl: link,
            directFileUrl: link.appending(path: "file")
        ))
        return MacCreateShareLinkSheet(store: Store(initialState: state) { CreateShareLinkFeature() })
    }

    #Preview("Edit") {
        MacEditShareSheet(store: Store(initialState: EditShareFeature.State(
            serverURL: sharedPreviewServerURL,
            share: .previewCard(hasPassword: true, expiresAt: Date().addingTimeInterval(86_400 * 7)),
            now: .now
        )) { EditShareFeature() } withDependencies: { $0.filesClient = .previewValue })
    }
#endif
