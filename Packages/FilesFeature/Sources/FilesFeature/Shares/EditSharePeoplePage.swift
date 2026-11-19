#if os(iOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    private enum Constants {
        static let avatarSize: CGFloat = .size32
        static let indicatorSize: CGFloat = .iconMedium
    }

    /// Everyone the server lets this share reach, searchable, ticked in place. Picks write straight
    /// into the edit draft, so Back keeps them and Save on the form sends them.
    struct EditSharePeoplePage: View {
        @Bindable var store: StoreOf<EditShareFeature>
        @State private var query = ""

        private var shownUsers: [User] {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return Array(store.shareableUsers) }
            return store.shareableUsers.filter { user in
                [user.displayName, user.username, user.email]
                    .compactMap(\.self)
                    .contains { $0.localizedStandardContains(trimmed) }
            }
        }

        var body: some View {
            DSGroupedList {
                Section {
                    content
                }
            }
            .sharedSheetList()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L10n.Common.search)
            .navigationTitle(L10n.Shared.people)
            .navigationBarTitleDisplayMode(.inline)
        }

        @ViewBuilder
        private var content: some View {
            if store.usersPhase == .loading {
                HStack(spacing: .space8) {
                    DSSpinner()
                    Text(L10n.CreateShare.loadingUsers).type(.body3(.regular), style: .secondary)
                }
            } else if shownUsers.isEmpty {
                Text(L10n.CreateShare.noOtherUsers).type(.body3(.regular), style: .secondary)
            } else {
                ForEach(shownUsers) { user in
                    row(user)
                }
            }
        }

        private func row(_ user: User) -> some View {
            let isSelected = store.selectedUserIDs.contains(user.id)
            let name = user.displayName ?? user.username
            return Button {
                store.send(.userToggled(user.id), animation: DSMotion.stateFade)
            } label: {
                HStack(spacing: .space12) {
                    AvatarView(displayName: name, size: Constants.avatarSize, tint: Color.categorical(for: name))
                    VStack(alignment: .leading, spacing: .space2) {
                        Text(name)
                            .type(.body2(.semibold), style: .primaryOnSurface)
                            .lineLimit(1)
                        if let email = user.email {
                            Text(email).type(.caption(.regular), style: .secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    DSSelectionIndicator(isSelected: isSelected, size: Constants.indicatorSize)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(DSPressableButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .hapticFeedback(.selection, trigger: isSelected)
        }
    }

    @MainActor
    private func peoplePreview(_ mutate: (inout EditShareFeature.State) -> Void) -> some View {
        NavigationStack {
            EditSharePeoplePage(store: editSharePreviewStore(.previewCard(target: .users), mutate: mutate))
        }
    }

    #Preview("Loaded, some picked") {
        peoplePreview {
            $0.usersPhase = .loaded
            $0.shareableUsers = IdentifiedArray(uniqueElements: Share.previewShareableUsers)
            $0.selectedUserIDs = ["u4", "u5", "u6"]
        }
    }

    #Preview("Loading, dark") {
        peoplePreview { $0.usersPhase = .loading }
            .preferredColorScheme(.dark)
    }

    #Preview("Nobody to pick") {
        peoplePreview { $0.usersPhase = .loaded }
    }

    #Preview("Large type") {
        peoplePreview {
            $0.usersPhase = .loaded
            $0.shareableUsers = IdentifiedArray(uniqueElements: Share.previewShareableUsers)
            $0.selectedUserIDs = ["u4"]
        }
        .dynamicTypeSize(.accessibility2)
    }
#endif
