import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

private enum Constants {
    static let headerIconSize: CGFloat = .iconMedium
    static let closeIconSize: CGFloat = .iconXSmall
    static let closeButtonPadding: CGFloat = .space8
    static let contentSpacing: CGFloat = .space16
    static let sectionSpacing: CGFloat = .space8
    static let horizontalPadding: CGFloat = .space16
    static let verticalPadding: CGFloat = .space16
    static let cardCornerRadius: CGFloat = .radiusCard
    static let cardPadding: CGFloat = .space12
    static let userAvatarSize: CGFloat = .size32
    static let selectionIconSize: CGFloat = .iconSmall
}

/// The "Edit Share Link" sheet — `PUT /api/shares/:id`. Mirrors `CreateShareLinkSheet`'s
/// form; the shared path is fixed and the password is keep / change / remove since its
/// current value can't be read back.
struct EditShareSheet: View {
    @Bindable var store: StoreOf<EditShareFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                formContent
                    .padding(.horizontal, Constants.horizontalPadding)
                    .padding(.vertical, Constants.verticalPadding)
            }
        }
        .background(Color.backgroundPrimary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack {
            HStack(spacing: .space8) {
                IconKit.rename
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.accent)
                    .frame(width: Constants.headerIconSize, height: Constants.headerIconSize)
                Text(L10n.EditShare.title).type(.headline3, style: .primary(for: .label))
            }
            Spacer()
            Button { dismiss() } label: {
                IconKit.close
                    .resizable()
                    .foregroundStyle(Color.primaryDS)
                    .frame(width: Constants.closeIconSize, height: Constants.closeIconSize)
                    .padding(Constants.closeButtonPadding)
                    .background(Circle().fill(Color.backgroundSecondary))
            }
            .buttonStyle(DSHapticButtonStyle())
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, .space16)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: Constants.contentSpacing) {
            if let errorMessage = store.errorMessage {
                DSErrorCard(errorMessage)
            }

            sourceCard

            section(L10n.CreateShare.sectionLabel) {
                DSTextField(
                    L10n.CreateShare.sectionLabel,
                    text: $store.label.sending(\.labelChanged),
                    prompt: Text(verbatim: store.share.displayName)
                )
                .autocorrectionDisabled()
            }

            section(L10n.CreateShare.sectionAccessMode) {
                DSSegmentedControl(
                    options: ShareAccessMode.allCases,
                    selection: $store.accessMode.sending(\.accessModeChanged),
                    label: { $0.title }
                )
            }

            section(L10n.CreateShare.sectionWhoCanAccess) {
                DSSegmentedControl(
                    options: ShareTarget.allCases,
                    selection: $store.target.sending(\.targetChanged),
                    label: { $0.title }
                )
                if store.target == .users {
                    userPicker
                }
            }

            DSToggleRow(
                title: L10n.CreateShare.togglePasswordProtect,
                icon: IconKit.lock,
                isOn: $store.wantsPassword.sending(\.wantsPasswordChanged)
            )
            if store.wantsPassword {
                DSSecureField(
                    L10n.Common.password,
                    text: $store.newPassword.sending(\.newPasswordChanged),
                    prompt: Text(store.share.hasPassword ? L10n.EditShare.passwordKeepHint : L10n.Common.password)
                )
            }

            DSToggleRow(
                title: L10n.CreateShare.toggleSetExpiration,
                icon: IconKit.calendar,
                isOn: $store.isExpiryEnabled.sending(\.expiryEnabledChanged)
            )
            if store.isExpiryEnabled {
                DatePicker(
                    L10n.CreateShare.fieldExpires,
                    selection: $store.expiresAt.sending(\.expiresAtChanged),
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .tint(Color.accent)
            }

            HStack(spacing: .space12) {
                DSButton(L10n.Common.cancel, style: .ghost) { dismiss() }
                DSButton(L10n.EditShare.save, style: .primary, isLoading: store.isSaving) {
                    store.send(.saveTapped)
                }
                .disabled(!store.isSaveEnabled)
            }
            .padding(.top, .space4)
        }
    }

    @ViewBuilder
    private var userPicker: some View {
        if store.isLoadingUsers {
            HStack(spacing: .space8) {
                ProgressView()
                Text(L10n.CreateShare.loadingUsers).type(.body3(.regular), style: .secondary)
            }
            .padding(.vertical, .space8)
        } else if store.shareableUsers.isEmpty {
            Text(L10n.CreateShare.noOtherUsers)
                .type(.body3(.regular), style: .secondary)
                .padding(.vertical, .space8)
        } else {
            VStack(spacing: 0) {
                ForEach(store.shareableUsers) { user in
                    let isSelected = store.selectedUserIDs.contains(user.id)
                    Button {
                        store.send(.userToggled(user.id))
                    } label: {
                        HStack(spacing: .space12) {
                            AvatarView(displayName: user.displayName ?? user.username, size: Constants.userAvatarSize)
                            VStack(alignment: .leading, spacing: .space2) {
                                Text(user.displayName ?? user.username)
                                    .type(.body3(.semibold), style: .primary(for: .label))
                                    .lineLimit(1)
                                if let email = user.email {
                                    Text(email).type(.caption(.regular), style: .secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            (isSelected ? IconKit.checkmarkCircleFill : IconKit.radioUnselected)
                                .resizable().scaledToFit()
                                .foregroundStyle(isSelected ? Color.accent : Color.secondaryDS)
                                .frame(width: Constants.selectionIconSize, height: Constants.selectionIconSize)
                        }
                        .padding(.vertical, .space8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DSHapticButtonStyle())
                    .hapticFeedback(.selection, trigger: isSelected)
                }
            }
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: .space2) {
            Text(L10n.CreateShare.sharingPrefix).type(.body3(.regular), style: .secondary)
            Text(store.share.displayName).type(.body2(.bold), style: .primary(for: .label)).lineLimit(1)
            if let path = store.share.sourcePath {
                Text(path).type(.caption(.regular), style: .tertiary).lineLimit(1).truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Constants.cardPadding)
        .background(RoundedRectangle(cornerRadius: Constants.cardCornerRadius).fill(Color.backgroundSecondary))
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
            DSFieldLabel(title)
            content()
        }
    }
}

// MARK: - Previews

@MainActor
private func editSharePreview(
    _ share: Share,
    configureClient: @Sendable (inout FilesClient) -> Void = { _ in }
) -> some View {
    var client = FilesClient.previewValue
    configureClient(&client)
    return Color.clear.sheet(isPresented: .constant(true)) {
        EditShareSheet(
            store: Store(
                initialState: EditShareFeature.State(serverURL: URL(string: "https://cloud.example.com")!, share: share)
            ) {
                EditShareFeature()
            } withDependencies: {
                $0.filesClient = client
            }
        )
    }
}

private func previewShare(
    hasPassword: Bool = false,
    target: ShareTarget = .anyone,
    expiresAt: Date? = nil,
    permittedUserIds: [String]? = nil
) -> Share {
    Share(
        id: "s1", shareToken: "AbC123xyz0", ownerId: "preview-user",
        sourcePath: "Documents/Bills/Electricity", isDirectory: true,
        accessMode: .readonly, sharingType: target, hasPassword: hasPassword,
        expiresAt: expiresAt, label: "Electricity", downloadCount: 3, lastAccessedAt: Date(),
        permittedUserIds: permittedUserIds, createdAt: Date(), updatedAt: Date()
    )
}

#Preview("Anyone, no password") {
    editSharePreview(previewShare())
}

#Preview("Password protected") {
    editSharePreview(previewShare(hasPassword: true))
}

#Preview("Specific users") {
    editSharePreview(previewShare(target: .users, permittedUserIds: ["u2"]))
}

#Preview("With expiry") {
    editSharePreview(previewShare(expiresAt: Date().addingTimeInterval(86_400 * 5)))
}

#Preview("Save error") {
    editSharePreview(previewShare()) {
        $0.updateShareLink = { _, _, _ in throw FilesClientError.server(statusCode: 403) }
    }
}
