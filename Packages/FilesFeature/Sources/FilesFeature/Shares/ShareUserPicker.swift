import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// The people a share link can be limited to, on the Create Share Link sheet: a spinner while they
/// load, a note when there is nobody else, otherwise one row each to tick.
struct ShareUserPicker: View {
    let store: StoreOf<CreateShareLinkFeature>

    private enum Constants {
        static let avatarSize: CGFloat = .size32
        static let indicatorSize: CGFloat = .iconSmall
    }

    var body: some View {
        if store.usersPhase == .loading {
            HStack(spacing: .space8) {
                DSSpinner()
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
                            AvatarView(displayName: user.displayLabel, size: Constants.avatarSize)
                            VStack(alignment: .leading, spacing: .space2) {
                                Text(user.displayLabel)
                                    .type(.body3(.semibold), style: .primaryOnSurface)
                                    .lineLimit(1)
                                if let email = user.email {
                                    Text(email).type(.caption(.regular), style: .secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            DSSelectionIndicator(isSelected: isSelected, size: Constants.indicatorSize)
                        }
                        .padding(.vertical, .space8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DSPressableButtonStyle())
                    .hapticFeedback(.selection, trigger: isSelected)
                }
            }
        }
    }
}

@MainActor
private func shareUserPickerPreview(_ mutate: (inout CreateShareLinkFeature.State) -> Void) -> some View {
    var state = CreateShareLinkFeature.State(
        serverURL: sharedPreviewServerURL,
        itemName: "Electricity",
        itemPath: "Documents/Bills",
        isDirectory: true,
        now: .now
    )
    mutate(&state)
    return ShareUserPicker(store: Store(initialState: state) { CreateShareLinkFeature() })
        .padding()
}

#Preview("Loading") {
    shareUserPickerPreview { $0.usersPhase = .loading }
}

#Preview("Nobody else") {
    shareUserPickerPreview { $0.usersPhase = .loaded }
}

#Preview("People") {
    shareUserPickerPreview {
        $0.usersPhase = .loaded
        $0.shareableUsers = [
            User(id: "u2", username: "lea", email: "lea@example.com", displayName: "Lea Martin"),
            User(id: "u3", username: "sam", email: nil),
        ]
        $0.selectedUserIDs = ["u2"]
    }
}
