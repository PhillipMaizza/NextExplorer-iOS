#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let chipAvatar: CGFloat = .size20
        static let chipHeight: CGFloat = 26
        static let addIcon: CGFloat = .iconXSmall
        static let removeGlyph: CGFloat = 9
    }

    struct MacShareUserTokenField: View {
        let users: [User]
        let selectedUserIDs: Set<User.ID>
        let onToggleUser: (User.ID) -> Void

        @State private var isPickerOpen = false

        private var selectedUsers: [User] {
            users.filter { selectedUserIDs.contains($0.id) }
        }

        private var canAddMore: Bool {
            selectedUserIDs.count < users.count
        }

        var body: some View {
            DSFlowLayout(horizontalSpacing: .space4, verticalSpacing: .space4) {
                ForEach(selectedUsers) { chip($0) }
                if canAddMore {
                    addButton
                }
            }
            .padding(.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .macFieldChrome(isFocused: isPickerOpen, size: .flexible)
            .contentShape(Rectangle())
            .onTapGesture {
                if canAddMore {
                    isPickerOpen = true
                }
            }
            .popover(isPresented: $isPickerOpen, arrowEdge: .bottom) {
                MacSharePeoplePopover(
                    users: users,
                    selectedUserIDs: selectedUserIDs,
                    onAdd: onToggleUser
                )
            }
            .onChange(of: canAddMore) {
                if !canAddMore {
                    isPickerOpen = false
                }
            }
        }

        private var addButton: some View {
            Button { isPickerOpen = true } label: {
                Label {
                    Text(L10n.CreateShare.addPeople).type(.body2(.regular))
                } icon: {
                    IconKit.plus
                        .resizable()
                        .scaledToFit()
                        .frame(width: Metrics.addIcon, height: Metrics.addIcon)
                }
                .foregroundStyle(Color.macChromeSecondary)
                .padding(.horizontal, .space8)
                .frame(height: Metrics.chipHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        private func chip(_ user: User) -> some View {
            let name = user.displayLabel
            return HStack(spacing: .space4) {
                AvatarView.person(name, size: Metrics.chipAvatar)
                Text(name)
                    .type(.body3(.regular))
                    .lineLimit(1)
                Button { onToggleUser(user.id) } label: {
                    IconKit.close
                        .resizable()
                        .scaledToFit()
                        .fontWeight(.semibold)
                        .frame(width: Metrics.removeGlyph, height: Metrics.removeGlyph)
                        .foregroundStyle(Color.macChromeSecondary)
                        .frame(width: Metrics.chipAvatar, height: Metrics.chipAvatar)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabelWithTooltip(L10n.Common.remove)
            }
            .padding(.leading, .space4)
            .padding(.trailing, .space4)
            .frame(height: Metrics.chipHeight)
            .background(Capsule().fill(Color.macSegment))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(name)
            .macDialogReveal()
        }
    }

    private struct TokenFieldPreview: View {
        @State var selected: Set<User.ID>

        var body: some View {
            MacShareUserTokenField(
                users: Share.previewShareableUsers,
                selectedUserIDs: selected,
                onToggleUser: { id in
                    if selected.remove(id) == nil {
                        selected.insert(id)
                    }
                }
            )
            .padding(MacInspectorMetrics.padding)
            .frame(width: MacFormSheetMetrics.width)
        }
    }

    #Preview("Nobody picked") {
        TokenFieldPreview(selected: [])
    }

    #Preview("Two picked") {
        TokenFieldPreview(selected: Set(Share.previewShareableUsers.prefix(2).map(\.id)))
    }

    #Preview("Everyone picked") {
        TokenFieldPreview(selected: Set(Share.previewShareableUsers.map(\.id)))
    }
#endif
