#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    /// The fields Create Share Link and Edit Share have in common, stacked in a `MacFormSheet`:
    /// what is shared, its label, access, who can open it, password and expiry.
    struct MacShareFormFields<Link: View>: View {
        let itemName: String
        let isDirectory: Bool
        let location: String
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
        @ViewBuilder var link: () -> Link

        var body: some View {
            MacSheetSubject(name: itemName, isDirectory: isDirectory, location: location)
            link()
            MacLabeledField(L10n.CreateShare.sectionLabel) {
                MacTextField(L10n.CreateShare.sectionLabel, text: label, prompt: itemName)
            }
            MacLabeledField(
                L10n.CreateShare.sectionAccessMode,
                hint: accessMode.wrappedValue.hint(isDirectory: isDirectory)
            ) {
                MacSegmentedPicker(
                    L10n.CreateShare.sectionAccessMode,
                    options: ShareAccessMode.allCases,
                    selection: accessMode
                ) { $0.title }
            }
            MacLabeledField(
                L10n.CreateShare.sectionWhoCanAccess,
                hint: target.wrappedValue.hint
            ) {
                MacSegmentedPicker(
                    L10n.CreateShare.sectionWhoCanAccess,
                    options: ShareTarget.allCases,
                    selection: target
                ) { $0.title }
            }
            if target.wrappedValue == .users {
                MacShareUserPicker(
                    users: users,
                    selectedUserIDs: selectedUserIDs,
                    usersPhase: usersPhase,
                    onToggleUser: onToggleUser
                )
            }
            MacFormGroup {
                if target.wrappedValue == .anyone {
                    MacToggleOption(L10n.CreateShare.togglePasswordProtect, isOn: isPasswordOn) {
                        MacSecureField(L10n.Common.password, text: password, prompt: Text(passwordPrompt))
                    }
                }
                MacToggleOption(L10n.CreateShare.fieldExpires, isOn: isExpiryOn) {
                    MacDatePopup(L10n.CreateShare.fieldExpires, date: expiresAt, in: Date()...)
                }
            }
        }
    }

    extension MacShareFormFields where Link == EmptyView {
        init(
            itemName: String,
            isDirectory: Bool,
            location: String,
            label: Binding<String>,
            accessMode: Binding<ShareAccessMode>,
            target: Binding<ShareTarget>,
            users: [User],
            selectedUserIDs: Set<User.ID>,
            usersPhase: DataPhase,
            onToggleUser: @escaping (User.ID) -> Void,
            isPasswordOn: Binding<Bool>,
            password: Binding<String>,
            passwordPrompt: String,
            isExpiryOn: Binding<Bool>,
            expiresAt: Binding<Date>
        ) {
            self.init(
                itemName: itemName,
                isDirectory: isDirectory,
                location: location,
                label: label,
                accessMode: accessMode,
                target: target,
                users: users,
                selectedUserIDs: selectedUserIDs,
                usersPhase: usersPhase,
                onToggleUser: onToggleUser,
                isPasswordOn: isPasswordOn,
                password: password,
                passwordPrompt: passwordPrompt,
                isExpiryOn: isExpiryOn,
                expiresAt: expiresAt
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
        .padding(.space24)
        .previewCanvasWidth(.sheet)
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
