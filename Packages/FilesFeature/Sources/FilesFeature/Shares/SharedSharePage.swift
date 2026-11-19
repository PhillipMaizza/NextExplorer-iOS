import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let actionHeight: CGFloat = .size48
    static let deletingOpacity: Double = 0.4
}

/// One share in the item sheet: the item, the copy split button, who it reaches, then its facts
/// and Edit and Delete. With me drops every owner control and says who controls the share. The
/// sheet's root when the item has one share, otherwise pushed from the share list.
struct SharedSharePage: View {
    let store: StoreOf<SharedFeature>
    let segment: SharedFeature.Segment
    let item: SharedFeature.Item
    let share: Share
    let isPushed: Bool
    let onCopied: (String) -> Void

    @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue
    @State private var directLinkMode: DirectLinkMode = .auto

    private var isByMe: Bool {
        segment == .byMe
    }

    private var isExpired: Bool {
        store.state.isExpired(share)
    }

    private var isDeleting: Bool {
        store.deletingIDs.contains(share.id)
    }

    private var dateFormat: DateDisplayFormat {
        DateDisplayFormat(rawValue: dateFormatRaw) ?? .system
    }

    private var badge: SharedFeature.ShareBadge? {
        item.badges.first { $0.id == share.id }
    }

    private var sharerName: String {
        badge?.people.first?.name ?? store.state.sharedByLabel(for: share)
    }

    var body: some View {
        DSGroupedList {
            Section {
                SharedDetailHero(
                    share: share,
                    iconName: item.name,
                    title: isPushed ? share.trimmedLabel ?? item.name : item.name,
                    subtitle: isByMe
                        ? SharedDetailHero.fullPath(of: share) ?? item.name
                        : L10n.Shared.fromSharer(sharerName),
                    serverURL: store.serverURL,
                    isByMe: isByMe,
                    isExpired: isExpired
                )
                .clearRow()
                if isByMe {
                    SharedCopyLinkButton(
                        share: share,
                        serverURL: store.serverURL,
                        directLinkMode: directLinkMode,
                        isExpired: isExpired,
                        onCopied: onCopied,
                        onSetNewDate: { store.send(.editTapped(share)) }
                    )
                    .clearRow()
                    .padding(.top, .space12)
                }
            }

            if let badge {
                Section {
                    SharedPeopleCircles(badge: badge)
                        .padding(.vertical, .space4)
                } header: {
                    DSFieldLabel(isByMe ? L10n.Shared.metaSharedWith : L10n.Shared.metaSharedBy)
                }
            }

            Section {
                fact(L10n.Shared.metaAccess, share.accessMode.title)
                fact(L10n.Common.password, share.hasPassword ? L10n.Common.on : L10n.Common.off)
                fact(isExpired ? L10n.Shared.metaExpired : L10n.Shared.metaExpires, expiresValue, style: expiresStyle)
                if isByMe {
                    DSMenuPickerRow(selection: $directLinkMode, value: directLinkMode.title) {
                        ForEach(DirectLinkMode.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Text(share.isDirectory ? L10n.Shared.folderLinkOpensAs : L10n.Shared.fileLinkOpensAs)
                            .type(.body2(.regular), style: .primaryOnSurface)
                    }
                    .tint(Color.secondaryDS)
                }
            } footer: {
                if isByMe, isExpired, let expiresAt = share.expiresAt {
                    Text(L10n.Shared.expiredFooter(dateFormat.string(from: expiresAt)))
                        .type(.body3(.regular), style: .error)
                }
            }

            Section {
                fact(L10n.Shared.metaLabel, share.trimmedLabel ?? L10n.Common.none)
                fact(
                    isByMe ? L10n.Shared.metaShared : L10n.Shared.metaReceived,
                    dateFormat.string(from: share.createdAt)
                )
                if isByMe {
                    fact(
                        L10n.Shared.metaLastOpened,
                        share.lastAccessedAt.map(OfflineRelativeTime.string(from:)) ?? L10n.Common.never
                    )
                    fact(L10n.Shared.metaDownloads, share.downloadCount.formatted())
                }
            } footer: {
                if !isByMe {
                    Text(L10n.Shared.controlsShare(sharerName)).type(.body3(.regular), style: .secondary)
                }
            }

            if isByMe {
                Section {
                    HStack(spacing: .space8) {
                        action(L10n.Common.edit, style: .primaryOnSurface) { store.send(.editTapped(share)) }
                        action(L10n.Common.delete, style: .error) { store.send(.deleteTapped(share)) }
                            .accessibilityIdentifier(AccessibilityIdentifiers.Shared.deleteShare)
                    }
                    .clearRow()
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundPrimary)
        .opacity(isDeleting ? Constants.deletingOpacity : 1)
        .disabled(isDeleting)
        .navigationTitle(isPushed ? item.name : "")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var expiresValue: String {
        guard let expiresAt = share.expiresAt else { return L10n.Common.never }
        let date = dateFormat.string(from: expiresAt)
        if case let .daysLeft(days) = store.state.expiryNotice(for: share) {
            return L10n.Shared.statusStep(date, L10n.Shared.daysLeft(days))
        }
        return date
    }

    private var expiresStyle: Typography.TextStyle {
        switch store.state.expiryNotice(for: share) {
        case .expired: .error
        case .daysLeft: .warning
        case nil: .secondary
        }
    }

    private func fact(_ label: String, _ value: String, style: Typography.TextStyle = .secondary) -> some View {
        HStack(spacing: .space12) {
            Text(label).type(.body2(.regular), style: .primaryOnSurface)
            Spacer(minLength: .space8)
            Text(value)
                .type(.body2(.regular), style: style)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func action(_ title: String, style: Typography.TextStyle, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .type(.body2(.semibold), style: style)
                .frame(maxWidth: .infinity, minHeight: Constants.actionHeight)
                .background(RoundedRectangle(cornerRadius: .radiusCard, style: .continuous)
                    .fill(Color.backgroundSecondary))
                .contentShape(Rectangle())
        }
        .buttonStyle(DSPressableButtonStyle())
    }
}

extension View {
    /// A list row with no card behind it, for content that draws its own surface.
    func clearRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

#Preview("Page: public link expiring soon") {
    sharedDetailPreview(.byMe, "personal:Photos/2026/Vacation Photos")
}

#Preview("Page: people, read and write") {
    sharedDetailPreview(.byMe, "personal:Work/Team Roadmap", pushed: "s5")
}

#Preview("Page: expired") {
    sharedDetailPreview(.byMe, "personal:Design/Brand/Logo final.png")
}

#Preview("Page: deleting") {
    sharedDetailPreview(.byMe, "personal:Finance/Budget 2027.xlsx") { $0.deletingIDs = ["s8"] }
}

#Preview("Page: with me, dark") {
    sharedDetailPreview(.withMe, "w2")
        .preferredColorScheme(.dark)
}

#Preview("Page: large type") {
    sharedDetailPreview(.byMe, "personal:Work/Meeting notes.md")
        .dynamicTypeSize(.accessibility2)
}
