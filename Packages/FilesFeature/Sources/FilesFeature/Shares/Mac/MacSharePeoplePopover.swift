#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 300
        static let rowAvatar: CGFloat = .size24
        static let estimatedRowHeight: CGFloat = 36
        static let visibleRows: CGFloat = 5.5
        static let searchIcon: CGFloat = .iconXSmall
    }

    struct MacSharePeoplePopover: View {
        let users: [User]
        let selectedUserIDs: Set<User.ID>
        let onAdd: (User.ID) -> Void

        @State private var query = ""
        @State private var highlightedID: User.ID?
        @State private var rowHeight: CGFloat?
        @FocusState private var isSearchFocused: Bool

        private var matches: [User] {
            let needle = query.trimmingCharacters(in: .whitespaces)
            return users.filter { user in
                !selectedUserIDs.contains(user.id)
                    && (needle.isEmpty || [user.displayName, user.username, user.email]
                        .compactMap(\.self)
                        .contains { $0.localizedCaseInsensitiveContains(needle) })
            }
        }

        private var highlightedIndex: Int? {
            matches.firstIndex { $0.id == highlightedID } ?? (matches.isEmpty ? nil : 0)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: .space8) {
                searchField
                if matches.isEmpty {
                    Text(L10n.EmptyState.noSearchMatches(query))
                        .type(.body3(.regular), style: .secondary)
                        .padding(.space8)
                } else {
                    list
                }
            }
            .padding(.space12)
            .frame(width: Metrics.width)
            .onAppear { isSearchFocused = true }
            .onChange(of: query) { highlightedID = nil }
        }

        private var searchField: some View {
            HStack(spacing: .space8) {
                IconKit.search
                    .resizable()
                    .scaledToFit()
                    .frame(width: Metrics.searchIcon, height: Metrics.searchIcon)
                    .foregroundStyle(Color.macChromeSecondary)
                    .accessibilityHidden(true)
                TextField(
                    L10n.CreateShare.addPeople,
                    text: $query,
                    prompt: Text(L10n.Common.search).foregroundStyle(Color.macChromeSecondary)
                )
                .textFieldStyle(.plain)
                .labelsHidden()
                .type(.body2(.regular))
                .focused($isSearchFocused)
                .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                .onKeyPress(.upArrow) { moveHighlight(by: -1) }
                .onSubmit(addHighlighted)
            }
            .padding(.horizontal, .space8)
            .macFieldChrome(isFocused: isSearchFocused)
        }

        private var list: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: .zero) {
                        ForEach(matches) { user in
                            row(user, isHighlighted: user.id == matches[safe: highlightedIndex]?.id)
                                .id(user.id)
                                .onHover { isHovering in
                                    if isHovering {
                                        highlightedID = user.id
                                    }
                                }
                        }
                    }
                }
                .frame(maxHeight: (rowHeight ?? Metrics.estimatedRowHeight) * Metrics.visibleRows)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: highlightedID) {
                    if let highlightedID {
                        proxy.scrollTo(highlightedID)
                    }
                }
            }
        }

        private func row(_ user: User, isHighlighted: Bool) -> some View {
            Button { onAdd(user.id) } label: {
                HStack(spacing: .zero) {
                    MacSharePersonLabel(
                        name: user.displayLabel,
                        email: user.email,
                        avatarSize: Metrics.rowAvatar,
                        nameType: .body2(.regular),
                        nameLineLimit: 2
                    )
                    Spacer(minLength: .zero)
                }
                .padding(.horizontal, .space8)
                .padding(.vertical, .space4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
                        .fill(isHighlighted ? Color.macSegment : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isHighlighted ? .isSelected : [])
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = min(rowHeight ?? $0, $0) }
        }

        private func moveHighlight(by step: Int) -> KeyPress.Result {
            guard let index = highlightedIndex else { return .ignored }
            let next = min(max(index + step, 0), matches.count - 1)
            highlightedID = matches[next].id
            return .handled
        }

        private func addHighlighted() {
            guard let user = matches[safe: highlightedIndex] else { return }
            let nextIndex = highlightedIndex.map { $0 + 1 }
            highlightedID = matches[safe: nextIndex]?.id
            onAdd(user.id)
            query = ""
        }
    }

    private struct PeoplePopoverPreview: View {
        @State var selected: Set<User.ID>

        var body: some View {
            MacSharePeoplePopover(
                users: Share.previewShareableUsers,
                selectedUserIDs: selected,
                onAdd: { selected.insert($0) }
            )
        }
    }

    #Preview("Nobody picked") {
        PeoplePopoverPreview(selected: [])
    }

    #Preview("One picked") {
        PeoplePopoverPreview(selected: [Share.previewShareableUsers[0].id])
    }
#endif
