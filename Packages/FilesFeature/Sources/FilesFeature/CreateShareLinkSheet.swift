import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI
import UIKit

private enum Constants {
    static let contentSpacing: CGFloat = .space16
    static let sectionSpacing: CGFloat = .space8
    static let horizontalPadding: CGFloat = .space16
    static let verticalPadding: CGFloat = .space16
    static let cardCornerRadius: CGFloat = .radiusCard
    static let cardPadding: CGFloat = .space12
    static let fieldHeight: CGFloat = .size48
    static let fieldHorizontalPadding: CGFloat = .space12
    static let copyButtonWidth: CGFloat = .size48
    static let copyIconSize: CGFloat = .iconSmall
    static let userAvatarSize: CGFloat = .size32
    static let copyFeedbackSeconds: Double = 2
    static let maxHeightFraction: CGFloat = 0.9
}

/// The "Create Share Link" sheet — mirrors the web client's `ShareDialog.vue`, in the app's
/// design-system idiom. Two phases: the form, then (`store.createdShare != nil`) the
/// created-link confirmation.
struct CreateShareLinkSheet: View {
    @Bindable var store: StoreOf<CreateShareLinkFeature>
    @Environment(\.dismiss) private var dismiss
    @State private var copiedField: CopiedField?

    private enum CopiedField: Equatable { case shareLink, directLink }

    var body: some View {
        DynamicHeightSheet(maxHeightFraction: Constants.maxHeightFraction) {
            VStack(alignment: .leading, spacing: Constants.contentSpacing) {
                DSSheetHeader(
                    icon: IconKit.shareLink,
                    title: store.createdShare != nil ? L10n.CreateShare.titleCreated : L10n.CreateShare.title,
                    closeAccessibilityLabel: L10n.Common.close,
                    onClose: { dismiss() }
                )
                if store.createdShare != nil {
                    createdContent
                } else {
                    formContent
                }
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
        } footer: {
            footerButtons
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        Group {
            if store.createdShare != nil {
                DSButton(L10n.Common.done, style: .primary) { dismiss() }
            } else {
                HStack(spacing: .space12) {
                    DSButton(L10n.Common.cancel, style: .ghost) { dismiss() }
                    DSButton(L10n.CreateShare.submit, style: .primary, isLoading: store.isCreating) {
                        store.send(.createTapped)
                    }
                    .disabled(!store.isCreateEnabled)
                }
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, Constants.sectionSpacing)
        .padding(.bottom, Constants.verticalPadding)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundPrimary)
    }

    // MARK: Form

    private var formContent: some View {
        VStack(alignment: .leading, spacing: Constants.contentSpacing) {
            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .type(.body3(.semibold), style: .error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Constants.cardPadding)
                    .background(RoundedRectangle(cornerRadius: Constants.cardCornerRadius).fill(Color.negative.opacity(0.12)))
            }

            sourceCard

            section(L10n.CreateShare.sectionLabel) {
                DSTextField(L10n.CreateShare.sectionLabel, text: $store.label.sending(\.labelChanged), prompt: Text(verbatim: store.itemName))
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
                isOn: $store.isPasswordEnabled.sending(\.passwordEnabledChanged)
            )
            if store.isPasswordEnabled {
                DSSecureField(L10n.Common.password, text: $store.password.sending(\.passwordChanged), prompt: Text(L10n.Common.password))
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
                                .frame(width: Constants.copyIconSize, height: Constants.copyIconSize)
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
            Text(store.itemName).type(.body2(.bold), style: .primary(for: .label)).lineLimit(1)
            Text(store.sourcePath).type(.caption(.regular), style: .tertiary).lineLimit(1).truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Constants.cardPadding)
        .background(RoundedRectangle(cornerRadius: Constants.cardCornerRadius).fill(Color.backgroundSecondary))
    }

    // MARK: Created

    @ViewBuilder
    private var createdContent: some View {
        if let created = store.createdShare {
            VStack(alignment: .leading, spacing: Constants.contentSpacing) {
                HStack(spacing: .space8) {
                    IconKit.checkmark
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.positive)
                        .frame(width: Constants.copyIconSize, height: Constants.copyIconSize)
                    Text(L10n.CreateShare.createdBanner).type(.body2(.semibold), style: .success)
                    Spacer(minLength: 0)
                }
                .padding(Constants.cardPadding)
                .background(RoundedRectangle(cornerRadius: Constants.cardCornerRadius).fill(Color.positive.opacity(0.12)))

                section(L10n.CreateShare.sectionShareLink) {
                    copyRow(value: created.shareUrl.absoluteString, field: .shareLink) {
                        copy(created.shareUrl.absoluteString, as: .shareLink)
                    }
                }

                VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
                    HStack(spacing: .space8) {
                        Text(created.share.isDirectory ? L10n.CreateShare.directFolderLink : L10n.CreateShare.directFileLink)
                            .type(.body2(.semibold), style: .primary(for: .label))
                        Spacer()
                        Picker(L10n.CreateShare.directLinkMode, selection: $store.directLinkMode.sending(\.directLinkModeChanged)) {
                            ForEach(DirectLinkMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(Color.secondaryDS)
                    }
                    copyRow(value: (store.directLink ?? created.directFileUrl).absoluteString, field: .directLink) {
                        copy((store.directLink ?? created.directFileUrl).absoluteString, as: .directLink)
                    }
                }

                summaryRows(for: created)
            }
        }
    }

    private var recipientNames: String {
        let names = store.shareableUsers
            .filter { store.selectedUserIDs.contains($0.id) }
            .map { $0.displayName ?? $0.username }
        return names.isEmpty ? L10n.CreateShare.summarySpecificPeople : names.joined(separator: ", ")
    }

    private func summaryRows(for created: CreatedShare) -> some View {
        VStack(alignment: .leading, spacing: .space12) {
            summaryRow(IconKit.lock, L10n.CreateShare.summaryAccess, created.share.accessMode.title)
            summaryRow(
                created.share.sharingType == .anyone ? IconKit.web : IconKit.people,
                L10n.CreateShare.summarySharedWith,
                created.share.sharingType == .anyone ? L10n.Shared.anyoneWithLink : recipientNames
            )
            if created.share.hasPassword {
                summaryRow(IconKit.lock, L10n.Common.password, L10n.CreateShare.summaryPasswordProtected)
            }
            if let expiresAt = created.share.expiresAt {
                summaryRow(IconKit.calendar, L10n.CreateShare.summaryExpires, Self.summaryDateFormatter.string(from: expiresAt))
            }
        }
    }

    private func summaryRow(_ icon: Image, _ label: String, _ value: String) -> some View {
        HStack(spacing: .space8) {
            icon
                .resizable().scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .frame(width: Constants.copyIconSize, height: Constants.copyIconSize)
            Text(label).type(.body2(.regular), style: .secondary)
            Spacer()
            Text(value)
                .type(.body2(.semibold), style: .primary(for: .label))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: Shared pieces

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
            DSFieldLabel(title)
            content()
        }
    }

    private func copyRow(value: String, field: CopiedField, action: @escaping () -> Void) -> some View {
        HStack(spacing: .space8) {
            Text(value)
                .type(.body3(.regular), style: .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Constants.fieldHorizontalPadding)
                .frame(height: Constants.fieldHeight)
                .background(RoundedRectangle(cornerRadius: .radiusControl).fill(Color.backgroundSecondary))

            Button(action: action) {
                (copiedField == field ? IconKit.checkmark : IconKit.copy)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: Constants.copyIconSize, height: Constants.copyIconSize)
                    .frame(width: Constants.copyButtonWidth, height: Constants.fieldHeight)
                    .background(RoundedRectangle(cornerRadius: .radiusControl).fill(copiedField == field ? Color.positive : Color.accent))
            }
            .buttonStyle(DSHapticButtonStyle())
        }
    }

    private func copy(_ string: String, as field: CopiedField) {
        UIPasteboard.general.string = string
        withAnimation { copiedField = field }
        Task {
            try? await Task.sleep(for: .seconds(Constants.copyFeedbackSeconds))
            withAnimation { if copiedField == field { copiedField = nil } }
        }
    }

    private static let summaryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview("Form") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CreateShareLinkSheet(
            store: Store(
                initialState: CreateShareLinkFeature.State(
                    serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
                    itemName: "Electricity",
                    itemPath: "Documents/Bills",
                    isDirectory: true
                )
            ) {
                CreateShareLinkFeature()
            } withDependencies: {
                $0.filesClient = .previewValue
            }
        )
    }
}

#Preview("Created") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CreateShareLinkSheet(
            store: Store(
                initialState: {
                    var state = CreateShareLinkFeature.State(
                        serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
                        itemName: "Electricity",
                        itemPath: "Documents/Bills",
                        isDirectory: true
                    )
                    state.createdShare = CreatedShare(
                        share: Share(
                            id: "s1", shareToken: "UrkLIGIHMF", ownerId: "u",
                            sourcePath: "Documents/Bills/Electricity", isDirectory: true,
                            accessMode: .readonly, sharingType: .anyone, hasPassword: false,
                            createdAt: Date(), updatedAt: Date()
                        ),
                        shareUrl: URL(string: "https://cloud.example.com/share/UrkLIGIHMF")!,
                        directFileUrl: URL(string: "https://cloud.example.com/api/share/UrkLIGIHMF/file")!
                    )
                    return state
                }()
            ) {
                CreateShareLinkFeature()
            } withDependencies: {
                $0.filesClient = .previewValue
            }
        )
    }
}
