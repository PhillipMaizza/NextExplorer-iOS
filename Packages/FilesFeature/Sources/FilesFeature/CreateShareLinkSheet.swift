import ComposableArchitecture
import CoreModels
import DesignSystem
import SwiftUI
import UIKit

private enum Constants {
    static let headerIconSize: CGFloat = .iconMedium
    static let closeIconSize: CGFloat = .iconXSmall
    static let closeButtonPadding: CGFloat = .space8
    static let contentSpacing: CGFloat = .space16
    static let sectionSpacing: CGFloat = .space8
    static let horizontalPadding: CGFloat = .space16
    static let verticalPadding: CGFloat = .space16
    static let cardCornerRadius: CGFloat = .radiusMedium
    static let cardPadding: CGFloat = .space12
    static let fieldHeight: CGFloat = .size48
    static let fieldHorizontalPadding: CGFloat = .space12
    static let copyButtonWidth: CGFloat = .size48
    static let copyIconSize: CGFloat = .iconSmall
    static let userAvatarSize: CGFloat = .size32
    static let copyFeedbackSeconds: Double = 2
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
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                Group {
                    if store.createdShare != nil {
                        createdContent
                    } else {
                        formContent
                    }
                }
                .padding(.horizontal, Constants.horizontalPadding)
                .padding(.vertical, Constants.verticalPadding)
            }
        }
        .background(Color.backgroundPrimary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            HStack(spacing: .space8) {
                IconKit.shareLink
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.accent)
                    .frame(width: Constants.headerIconSize, height: Constants.headerIconSize)
                Text(store.createdShare != nil ? "Share Created" : "Create Share Link")
                    .type(.headline3, style: .primary(for: .label))
            }
            Spacer()
            Button {
                dismiss()
            } label: {
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

    // MARK: Form

    private var formContent: some View {
        VStack(alignment: .leading, spacing: Constants.contentSpacing) {
            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .type(.body3(.regular), style: .error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Constants.cardPadding)
                    .background(RoundedRectangle(cornerRadius: Constants.cardCornerRadius).fill(Color.negative.opacity(0.12)))
            }

            sourceCard

            section("Label") {
                fieldBox {
                    TextField("Label", text: $store.label.sending(\.labelChanged), prompt: Text(verbatim: store.itemName))
                        .type(.body2(.regular))
                        .foregroundStyle(Color.primaryDS)
                        .autocorrectionDisabled()
                }
            }

            section("Access Mode") {
                DSSegmentedControl(
                    options: ShareAccessMode.allCases,
                    selection: $store.accessMode.sending(\.accessModeChanged),
                    label: { $0.title }
                )
            }

            section("Who can access") {
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
                title: "Password protect",
                icon: IconKit.lock,
                isOn: $store.isPasswordEnabled.sending(\.passwordEnabledChanged)
            )
            if store.isPasswordEnabled {
                fieldBox {
                    SecureField("Password", text: $store.password.sending(\.passwordChanged), prompt: Text(verbatim: "Password"))
                        .type(.body2(.regular))
                        .foregroundStyle(Color.primaryDS)
                }
            }

            DSToggleRow(
                title: "Set expiration date",
                icon: IconKit.calendar,
                isOn: $store.isExpiryEnabled.sending(\.expiryEnabledChanged)
            )
            if store.isExpiryEnabled {
                DatePicker(
                    "Expires",
                    selection: $store.expiresAt.sending(\.expiresAtChanged),
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .tint(Color.accent)
            }

            HStack(spacing: .space12) {
                DSButton("Cancel", style: .secondary) { dismiss() }
                DSButton("Create Share Link", style: .primary, isLoading: store.isCreating) {
                    store.send(.createTapped)
                }
                .disabled(!store.isCreateEnabled)
            }
            .padding(.top, .space4)
        }
    }

    @ViewBuilder
    private var userPicker: some View {
        if store.isLoadingUsers {
            HStack(spacing: .space8) {
                ProgressView()
                Text("Loading users\u{2026}").type(.body3(.regular), style: .secondary)
            }
            .padding(.vertical, .space8)
        } else if store.shareableUsers.isEmpty {
            Text("No other users to share with.")
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
            Text("Sharing:").type(.body3(.regular), style: .secondary)
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
                    Text("Share link created successfully!").type(.body2(.semibold), style: .success)
                    Spacer(minLength: 0)
                }
                .padding(Constants.cardPadding)
                .background(RoundedRectangle(cornerRadius: Constants.cardCornerRadius).fill(Color.positive.opacity(0.12)))

                section("Share Link") {
                    copyRow(value: created.shareUrl.absoluteString, field: .shareLink) {
                        copy(created.shareUrl.absoluteString, as: .shareLink)
                    }
                }

                VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
                    HStack(spacing: .space8) {
                        Text(created.share.isDirectory ? "Direct folder ZIP link" : "Direct file link")
                            .type(.body2(.semibold), style: .primary(for: .label))
                        Spacer()
                        Picker("Direct link mode", selection: $store.directLinkMode.sending(\.directLinkModeChanged)) {
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

                DSButton("Done", style: .primary) { dismiss() }
                    .padding(.top, .space4)
            }
        }
    }

    private var recipientNames: String {
        let names = store.shareableUsers
            .filter { store.selectedUserIDs.contains($0.id) }
            .map { $0.displayName ?? $0.username }
        return names.isEmpty ? "Specific people" : names.joined(separator: ", ")
    }

    private func summaryRows(for created: CreatedShare) -> some View {
        VStack(alignment: .leading, spacing: .space12) {
            summaryRow(IconKit.lock, "Access", created.share.accessMode.title)
            summaryRow(
                created.share.sharingType == .anyone ? IconKit.web : IconKit.people,
                "Shared with",
                created.share.sharingType == .anyone ? "Anyone with link" : recipientNames
            )
            if created.share.hasPassword {
                summaryRow(IconKit.lock, "Password", "Protected")
            }
            if let expiresAt = created.share.expiresAt {
                summaryRow(IconKit.calendar, "Expires", Self.summaryDateFormatter.string(from: expiresAt))
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
            Text(title).type(.body2(.semibold), style: .primary(for: .label))
            content()
        }
    }

    private func fieldBox(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(.horizontal, Constants.fieldHorizontalPadding)
            .frame(height: Constants.fieldHeight)
            .background(
                RoundedRectangle(cornerRadius: .radiusControl)
                    .stroke(Color.borderPrimary, lineWidth: .borderWidthHairline)
            )
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
