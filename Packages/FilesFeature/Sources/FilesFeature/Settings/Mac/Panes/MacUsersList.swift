#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let avatarSize: CGFloat = .size32
        static let rowHeight: CGFloat = .size56
        static let separatorInset: CGFloat = .space12 + .size32 + .space12
        static let shadowRadius: CGFloat = 1.5
        static let shadowOffset: CGFloat = 1
    }

    struct MacUsersList: View {
        static let width: CGFloat = 300
        @Bindable var store: StoreOf<UserManagementFeature>

        var body: some View {
            VStack(spacing: .zero) {
                MacTextField(
                    L10n.UserManagement.searchPrompt,
                    text: $store.searchQuery.sending(\.searchQueryChanged),
                    prompt: L10n.UserManagement.searchPrompt
                )
                .padding(.space12)
                ScrollView {
                    LazyVStack(spacing: .zero) {
                        content
                    }
                    .padding(.horizontal, .space8)
                    .padding(.bottom, .space8)
                }
            }
        }

        @ViewBuilder private var content: some View {
            if store.phase == .loading, store.users.isEmpty {
                MacSpinner()
                    .frame(maxWidth: .infinity)
                    .macMinHeight(.large)
            } else if let error = store.phase.errorMessage, store.users.isEmpty {
                VStack(alignment: .leading, spacing: .space8) {
                    MacNote(error, kind: .error)
                    Button(L10n.Common.retry) { store.send(.refreshRequested) }
                        .buttonStyle(.macDS(.secondary, size: .small))
                }
                .padding(.horizontal, .space4)
            } else if store.isSearchWithoutResults {
                MacTableEmptyLine(L10n.UserManagement.noSearchMatches(store.searchQuery))
            } else if store.users.isEmpty {
                MacTableEmptyLine(L10n.UserManagement.emptyList)
            } else {
                let users = store.displayedUsers
                ForEach(Array(users.enumerated()), id: \.element.id) { index, user in
                    let isSelected = user.id == store.detailUserID
                    MacUserListRow(user: user, isSelected: isSelected) {
                        if !isSelected {
                            store.send(.userTapped(user.id))
                        }
                    }
                    if index < users.count - 1 {
                        Rectangle()
                            .fill(Color.macLine)
                            .frame(height: .borderWidthHairline)
                            .padding(.leading, Metrics.separatorInset)
                            .padding(.trailing, .space12)
                            .opacity(isSelected || users[index + 1].id == store.detailUserID ? 0 : 1)
                    }
                }
            }
        }
    }

    private struct MacUserListRow: View {
        let user: User
        let isSelected: Bool
        let onSelect: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: onSelect) {
                HStack(spacing: .space12) {
                    AvatarView.person(user.displayLabel, size: Metrics.avatarSize)
                    VStack(alignment: .leading, spacing: .space2) {
                        Text(user.displayLabel)
                            .type(.body2(.semibold))
                        Text(user.email ?? "")
                            .type(.body3(.regular), style: .secondary)
                            .truncationMode(.middle)
                    }
                    .lineLimit(1)
                    Spacer(minLength: .space8)
                    if user.isAdmin {
                        MacChip.admin(size: .regular)
                    }
                }
                .foregroundStyle(Color.macChromeText)
                .padding(.horizontal, .space12)
                .frame(maxWidth: .infinity, minHeight: Metrics.rowHeight, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
                        .fill(fill)
                        .shadow(
                            color: isSelected ? .macCardShadow : .clear,
                            radius: Metrics.shadowRadius,
                            y: Metrics.shadowOffset
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .animation(DSMotion.quickFade, value: isHovered)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        private var fill: Color {
            if isSelected {
                return .macSelection
            }
            return isHovered ? .macChromeHover : .clear
        }
    }

    @MainActor
    private func usersListPreview(_ mutate: (inout UserManagementFeature.State) -> Void) -> some View {
        var state = UserManagementFeature.State(
            serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
            currentUserID: "u1"
        )
        mutate(&state)
        return MacUsersList(store: Store(initialState: state) { EmptyReducer() })
            .frame(width: MacUsersList.width)
            .background(Color.macRow)
    }

    #Preview("Users list") {
        usersListPreview {
            $0.users = IdentifiedArray(uniqueElements: User.previewManagedUsers)
            $0.phase = .loaded
            $0.detailUserID = User.previewManagedUsers.last?.id
        }
    }

    #Preview("Users list loading") {
        usersListPreview { $0.phase = .loading }
    }

    #Preview("Users list failed") {
        usersListPreview { $0.phase = .failed(L10n.Common.retry) }
    }

    #Preview("Users list no matches") {
        usersListPreview {
            $0.users = IdentifiedArray(uniqueElements: User.previewManagedUsers)
            $0.phase = .loaded
            $0.searchQuery = "zzz"
        }
    }
#endif
