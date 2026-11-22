#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let typeWidth: CGFloat = 110
        static let avatarSize: CGFloat = 26
    }

    struct MacUsersTable: View {
        let store: StoreOf<UserManagementFeature>

        var body: some View {
            VStack(alignment: .leading, spacing: .zero) {
                MacTableHeader {
                    sortHeader(.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    sortHeader(.email)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    sortHeader(.type)
                        .frame(width: Metrics.typeWidth, alignment: .leading)
                }
                if store.phase == .loading, store.users.isEmpty {
                    MacSpinner()
                        .frame(maxWidth: .infinity)
                        .frame(height: MacTableMetrics.rowHeight)
                } else if let error = store.phase.errorMessage, store.users.isEmpty {
                    HStack(spacing: .space12) {
                        MacNote(error, kind: .error)
                        Button(L10n.Common.retry) { store.send(.refreshRequested) }
                            .buttonStyle(.macDS(.secondary, size: .small))
                    }
                    .padding(.horizontal, .space12)
                } else if store.isSearchWithoutResults {
                    emptyLine(L10n.UserManagement.noSearchMatches(store.searchQuery))
                } else if store.users.isEmpty {
                    emptyLine(L10n.UserManagement.emptyList)
                } else {
                    ForEach(Array(store.displayedUsers.enumerated()), id: \.element.id) { index, user in
                        MacUserTableRow(
                            user: user,
                            isShaded: index.isMultiple(of: 2),
                            isSelected: user.id == store.detailUserID
                        ) {
                            if user.id != store.detailUserID {
                                store.send(.userTapped(user.id))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, -.space12)
        }

        private func sortHeader(_ option: UserManagementFeature.SortOption) -> some View {
            MacTableSortHeader(
                option.title,
                isSorted: store.sortOption == option,
                isAscending: store.sortDirection == .ascending
            ) {
                if store.sortOption == option {
                    store.send(.sortDirectionChanged(store.sortDirection == .ascending ? .descending : .ascending))
                } else {
                    store.send(.sortOptionChanged(option))
                }
            }
            .disabled(store.users.isEmpty)
        }

        private func emptyLine(_ text: String) -> some View {
            Text(text)
                .type(.body2(.regular), style: .secondary)
                .padding(.horizontal, .space12)
                .frame(height: MacTableMetrics.rowHeight)
        }
    }

    private struct MacUserTableRow: View {
        let user: User
        let isShaded: Bool
        let isSelected: Bool
        let onSelect: () -> Void

        var body: some View {
            Button(action: onSelect) {
                HStack(spacing: MacTableMetrics.columnSpacing) {
                    HStack(spacing: .space8) {
                        AvatarView(
                            displayName: user.displayLabel,
                            size: Metrics.avatarSize,
                            tint: Color.categorical(for: user.displayLabel)
                        )
                        Text(user.displayLabel)
                            .type(.body2(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(user.email ?? "")
                        .type(.body2(.regular))
                        .foregroundStyle(Color.macChromeSecondary)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                        if user.isAdmin {
                            MacChip(text: L10n.UserManagement.badgeAdmin, tone: .amber)
                        } else {
                            Text(L10n.MacSettings.roleUser)
                                .type(.body2(.regular))
                                .foregroundStyle(Color.macChromeSecondary)
                        }
                    }
                    .frame(width: Metrics.typeWidth, alignment: .leading)
                }
                .lineLimit(1)
                .foregroundStyle(Color.macChromeText)
                .macTableRow(isShaded: isShaded, isSelected: isSelected)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    @MainActor
    private func usersTablePreview(_ mutate: (inout UserManagementFeature.State) -> Void) -> some View {
        var state = UserManagementFeature.State(
            serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
            currentUserID: "u1"
        )
        mutate(&state)
        return MacUsersTable(store: Store(initialState: state) { EmptyReducer() })
            .padding(.space32)
            .frame(width: 760)
            .background(Color.macCard)
    }

    #Preview("Users table") {
        usersTablePreview {
            $0.users = IdentifiedArray(uniqueElements: User.previewManagedUsers)
            $0.phase = .loaded
            $0.detailUserID = User.previewManagedUsers.last?.id
        }
    }

    #Preview("Users table loading") {
        usersTablePreview { $0.phase = .loading }
    }

    #Preview("Users table failed") {
        usersTablePreview { $0.phase = .failed(L10n.Common.retry) }
    }

    #Preview("Users table no matches") {
        usersTablePreview {
            $0.users = IdentifiedArray(uniqueElements: User.previewManagedUsers)
            $0.phase = .loaded
            $0.searchQuery = "zzz"
        }
    }
#endif
