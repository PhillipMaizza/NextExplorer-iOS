#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    enum MacShareFormMetrics {
        static let sheetWidth: CGFloat = 760
        static let columnSpacing: CGFloat = .space24
    }

    /// The fields Create Share Link and Edit Share have in common, stacked in a `MacFormSheet`:
    /// what is shared, its label, access, who can open it, password and expiry.
    struct MacShareFormFields<Link: View>: View {
        let itemName: String
        let isDirectory: Bool
        let location: String
        let label: Binding<String>
        let accessChoice: Binding<ShareAccessChoice>
        let permissions: Binding<SharePermissions>
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
        var isWritable = true
        @ViewBuilder var link: () -> Link

        var body: some View {
            MacSheetSubject(name: itemName, isDirectory: isDirectory, location: location, label: label)
            link()
            HStack(alignment: .top, spacing: MacShareFormMetrics.columnSpacing) {
                MacShareAccessField(
                    isDirectory: isDirectory,
                    isWritable: isWritable,
                    choice: accessChoice,
                    permissions: permissions
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: MacFormSheetMetrics.spacing) {
                    MacLabeledField(L10n.CreateShare.sectionWhoCanAccess) {
                        MacSegmentedPicker(
                            L10n.CreateShare.sectionWhoCanAccess,
                            options: ShareTarget.allCases,
                            selection: target
                        ) { $0.title }
                        Text(target.wrappedValue.hint)
                            .type(.caption(.regular), style: .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .animation(nil, value: target.wrappedValue)
                    }
                    VStack(alignment: .leading, spacing: MacFormSheetMetrics.spacing) {
                        if target.wrappedValue == .users {
                            MacShareUserPicker(
                                users: users,
                                selectedUserIDs: selectedUserIDs,
                                usersPhase: usersPhase,
                                onToggleUser: onToggleUser
                            )
                        }
                        MacFormGroup {
                            MacShareVersionsOptions(permissions: permissions)
                            passwordOption
                            MacToggleOption(L10n.CreateShare.fieldExpires, isDetailTrailing: true, isOn: isExpiryOn) {
                                MacDatePopup(L10n.CreateShare.fieldExpires, date: expiresAt, in: Date()...)
                            }
                        }
                    }
                    .animation(nil, value: target.wrappedValue)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }

        private var passwordOption: some View {
            let isAvailable = target.wrappedValue == .anyone
            return MacToggleOption(
                L10n.CreateShare.togglePasswordProtect,
                subtitle: isAvailable ? nil : L10n.CreateShare.passwordAnyoneOnly,
                isOn: isAvailable ? isPasswordOn : .constant(false)
            ) {
                MacSecureField(L10n.Common.password, text: password, prompt: Text(passwordPrompt))
            }
            .disabled(!isAvailable)
            .opacity(isAvailable ? 1 : .opacityHalf)
        }
    }

    extension MacShareFormFields where Link == EmptyView {
        init(
            itemName: String,
            isDirectory: Bool,
            location: String,
            label: Binding<String>,
            accessChoice: Binding<ShareAccessChoice>,
            permissions: Binding<SharePermissions>,
            target: Binding<ShareTarget>,
            users: [User],
            selectedUserIDs: Set<User.ID>,
            usersPhase: DataPhase,
            onToggleUser: @escaping (User.ID) -> Void,
            isPasswordOn: Binding<Bool>,
            password: Binding<String>,
            passwordPrompt: String,
            isExpiryOn: Binding<Bool>,
            expiresAt: Binding<Date>,
            isWritable: Bool = true
        ) {
            self.init(
                itemName: itemName,
                isDirectory: isDirectory,
                location: location,
                label: label,
                accessChoice: accessChoice,
                permissions: permissions,
                target: target,
                users: users,
                selectedUserIDs: selectedUserIDs,
                usersPhase: usersPhase,
                onToggleUser: onToggleUser,
                isPasswordOn: isPasswordOn,
                password: password,
                passwordPrompt: passwordPrompt,
                isExpiryOn: isExpiryOn,
                expiresAt: expiresAt,
                isWritable: isWritable
            ) { EmptyView() }
        }
    }

    @MainActor
    private func shareFieldsPreview(target: ShareTarget, usersPhase: DataPhase = .loaded) -> some View {
        VStack(alignment: .leading, spacing: .space16) {
            MacShareFormFields(
                itemName: "Electricity",
                isDirectory: true,
                location: "Documents/Bills",
                label: .constant(""),
                accessChoice: .constant(.canDownload),
                permissions: .constant(SharePermissions()),
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
        .padding(.space24)
        .frame(width: MacShareFormMetrics.sheetWidth)
        .background(Color.macCard)
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
