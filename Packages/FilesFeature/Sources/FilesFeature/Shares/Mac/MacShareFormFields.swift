#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let avatarSize: CGFloat = .size24
        static let userListMaxHeight: CGFloat = 160
    }

    /// The fields Create Share Link and Edit Share have in common, as rows of a native
    /// `MacFormSheet`: what is shared, its label, access, who can open it, password and expiry.
    struct MacShareFormFields: View {
        let itemName: String
        let sourcePath: String?
        let label: Binding<String>
        let accessMode: Binding<ShareAccessMode>
        let target: Binding<ShareTarget>
        let users: [User]
        let selectedUserIDs: Set<User.ID>
        let usersPhase: DataPhase
        let onToggleUser: (User.ID) -> Void
        let isPasswordOn: Binding<Bool>
        let password: Binding<String>
        let passwordPrompt: String
        let isExpiryOn: Binding<Bool>
        let expiresAt: Binding<Date>

        var body: some View {
            MacSettingsRow(L10n.CreateShare.sharingPrefix) {
                Text(itemName).fontWeight(.semibold).lineLimit(1)
                if let sourcePath {
                    MacSettingsNote(sourcePath)
                }
            }
            MacSettingsRow(L10n.CreateShare.sectionLabel) {
                TextField(L10n.CreateShare.sectionLabel, text: label, prompt: Text(verbatim: itemName))
                    .labelsHidden()
                    .autocorrectionDisabled()
            }
            MacSettingsRow(L10n.CreateShare.sectionAccessMode) {
                Picker(L10n.CreateShare.sectionAccessMode, selection: accessMode) {
                    ForEach(ShareAccessMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            MacSettingsRow(L10n.CreateShare.sectionWhoCanAccess) {
                Picker(L10n.CreateShare.sectionWhoCanAccess, selection: target) {
                    ForEach(ShareTarget.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                if target.wrappedValue == .users {
                    userPicker
                }
            }
            MacSettingsRow(L10n.Common.password) {
                Toggle(L10n.CreateShare.togglePasswordProtect, isOn: isPasswordOn)
                if isPasswordOn.wrappedValue {
                    SecureField(L10n.Common.password, text: password, prompt: Text(passwordPrompt))
                        .labelsHidden()
                }
            }
            MacSettingsRow(L10n.CreateShare.fieldExpires) {
                Toggle(L10n.CreateShare.toggleSetExpiration, isOn: isExpiryOn)
                if isExpiryOn.wrappedValue {
                    DatePicker(L10n.CreateShare.fieldExpires, selection: expiresAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .fixedSize()
                }
            }
        }

        @ViewBuilder
        private var userPicker: some View {
            if usersPhase == .loading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(L10n.CreateShare.loadingUsers).foregroundStyle(.secondary)
                }
            } else if users.isEmpty {
                Text(L10n.CreateShare.noOtherUsers).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: .space4) {
                        ForEach(users) { user in
                            Toggle(isOn: Binding(get: { selectedUserIDs.contains(user.id) }, set: { _ in onToggleUser(user.id) })) {
                                HStack(spacing: .space8) {
                                    AvatarView(displayName: user.displayName ?? user.username, size: Metrics.avatarSize)
                                    Text(user.displayName ?? user.username).lineLimit(1)
                                    if let email = user.email {
                                        Text(email).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxHeight: Metrics.userListMaxHeight)
            }
        }
    }

    @MainActor
    private func shareFieldsPreview(target: ShareTarget, usersPhase: DataPhase = .loaded) -> some View {
        Form {
            MacShareFormFields(
                itemName: "Electricity",
                sourcePath: "Documents/Bills",
                label: .constant(""),
                accessMode: .constant(.readonly),
                target: .constant(target),
                users: User.previewManagedUsers,
                selectedUserIDs: [],
                usersPhase: usersPhase,
                onToggleUser: { _ in },
                isPasswordOn: .constant(true),
                password: .constant(""),
                passwordPrompt: "Required",
                isExpiryOn: .constant(false),
                expiresAt: .constant(Date())
            )
        }
        .formStyle(.columns)
        .padding(.space24)
        .frame(width: 520)
    }

    #Preview("Anyone") {
        shareFieldsPreview(target: .anyone)
    }

    #Preview("Users") {
        shareFieldsPreview(target: .users)
    }

    #Preview("Users loading") {
        shareFieldsPreview(target: .users, usersPhase: .loading)
    }
#endif
