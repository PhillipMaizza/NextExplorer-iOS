#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    struct MacShareUserPicker: View {
        let users: [User]
        let selectedUserIDs: Set<User.ID>
        let usersPhase: DataPhase
        let onToggleUser: (User.ID) -> Void

        var body: some View {
            if usersPhase == .loading {
                HStack(spacing: .space8) {
                    MacSpinner()
                    Text(L10n.CreateShare.loadingUsers).type(.body3(.regular), style: .secondary)
                }
            } else if users.isEmpty {
                Text(L10n.CreateShare.noOtherUsers).type(.body3(.regular), style: .secondary)
            } else {
                MacShareUserTokenField(
                    users: users,
                    selectedUserIDs: selectedUserIDs,
                    onToggleUser: onToggleUser
                )
            }
        }
    }

    #Preview("Loading") {
        MacShareUserPicker(users: [], selectedUserIDs: [], usersPhase: .loading, onToggleUser: { _ in })
            .padding(MacInspectorMetrics.padding)
            .frame(width: MacInspectorMetrics.width)
    }

    #Preview("No other users") {
        MacShareUserPicker(users: [], selectedUserIDs: [], usersPhase: .loaded, onToggleUser: { _ in })
            .padding(MacInspectorMetrics.padding)
            .frame(width: MacInspectorMetrics.width)
    }

    #Preview("User picker") {
        MacShareUserPicker(
            users: Share.previewShareableUsers,
            selectedUserIDs: [Share.previewShareableUsers[0].id],
            usersPhase: .loaded,
            onToggleUser: { _ in }
        )
        .padding(MacInspectorMetrics.padding)
        .frame(width: MacInspectorMetrics.width)
    }
#endif
