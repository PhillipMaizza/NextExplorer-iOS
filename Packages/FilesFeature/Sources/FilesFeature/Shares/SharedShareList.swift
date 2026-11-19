import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let audienceSize: CGFloat = .size40
    static let pairAvatarSize: CGFloat = .size24
    static let pairAvatarRing: CGFloat = .size2
    /// Pulls the second avatar back over the first so the pair overlaps.
    static let pairAvatarOffset: CGFloat = -.size4
    static let copySize: CGFloat = .size40
    static let copyGlyphSize: CGFloat = .iconSmall
    static let copyFillOpacity: Double = 0.2
}

/// The item sheet's root when the item has two or more shares: one row per share, oldest first.
/// A row pushes its share page; its round button copies the share link without opening it.
struct SharedShareList: View {
    let store: StoreOf<SharedFeature>
    let item: SharedFeature.Item
    let onCopied: (String) -> Void

    var body: some View {
        DSGroupedList {
            Section {
                SharedDetailHero(
                    share: item.shares[0],
                    iconName: item.name,
                    title: item.name,
                    subtitle: subtitle,
                    serverURL: store.serverURL,
                    isByMe: true,
                    isExpired: item.isExpired
                )
                .clearRow()
            }

            Section {
                ForEach(item.shares) { share in
                    NavigationLink(value: share.id) {
                        SharedShareListRow(
                            share: share,
                            badge: item.badges.first { $0.id == share.id },
                            notice: store.state.expiryNotice(for: share),
                            onCopy: {
                                PlatformPasteboard.copy(share.shareLink(serverURL: store.serverURL))
                                onCopied(L10n.Shared.copiedShareLink)
                            }
                        )
                    }
                    .disabled(store.deletingIDs.contains(share.id))
                }
            } header: {
                DSFieldLabel(L10n.Shared.shareCount(item.shares.count))
            } footer: {
                Text(L10n.Shared.listFooter).type(.body3(.regular), style: .secondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundPrimary)
    }

    private var subtitle: String {
        let downloads = L10n.Shared.downloadCount(item.shares.reduce(0) { $0 + $1.downloadCount })
        guard let path = SharedDetailHero.fullPath(of: item.shares[0]) else { return downloads }
        return L10n.Shared.statusStep(path, downloads)
    }
}

/// One share in the list: who it reaches, its label, a one line summary and a copy button.
private struct SharedShareListRow: View {
    let share: Share
    let badge: SharedFeature.ShareBadge?
    let notice: SharedFeature.ExpiryNotice?
    let onCopy: () -> Void

    @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue

    var body: some View {
        HStack(spacing: .space12) {
            audience
                .frame(width: Constants.audienceSize, height: Constants.audienceSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: .space2) {
                Text(title).type(.body2(.semibold), style: .primaryOnSurface)
                Text(status)
                    .type(.body3(.regular), style: notice == .expired ? .error : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onCopy) {
                IconKit.link
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.accentText)
                    .frame(width: Constants.copyGlyphSize, height: Constants.copyGlyphSize)
                    .frame(width: Constants.copySize, height: Constants.copySize)
                    .background(Circle().fill(Color.accent.opacity(Constants.copyFillOpacity)))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.Shared.copyShareLink)
        }
        .padding(.vertical, .space4)
    }

    @ViewBuilder
    private var audience: some View {
        let people = badge?.people ?? []
        if share.sharingType == .anyone {
            SharedIconCircle(icon: IconKit.web)
        } else if people.count < 2 {
            // One known face fills the slot; none yet falls back to a people glyph.
            if let person = people.first {
                AvatarView(
                    displayName: person.name,
                    size: Constants.audienceSize,
                    tint: Color.categorical(for: person.name)
                )
            } else {
                SharedIconCircle(icon: IconKit.people)
            }
        } else {
            ZStack {
                ForEach(Array(people.prefix(2).enumerated()), id: \.element.id) { index, person in
                    AvatarView(
                        displayName: person.name,
                        size: Constants.pairAvatarSize,
                        tint: Color.categorical(for: person.name)
                    )
                    .overlay(Circle().strokeBorder(Color.backgroundSecondary, lineWidth: Constants.pairAvatarRing))
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: index == 0 ? .topLeading : .bottomTrailing
                    )
                    .offset(
                        x: index == 0 ? 0 : Constants.pairAvatarOffset,
                        y: index == 0
                            ? 0
                            : Constants.pairAvatarOffset
                    )
                }
            }
        }
    }

    private var title: String {
        share.trimmedLabel ?? (share.sharingType == .anyone ? L10n.Shared.publicLink : L10n.Shared.people)
    }

    /// "5 people · can edit · password · never expires", joined through the localized step.
    private var status: String {
        let audience = share.sharingType == .anyone
            ? L10n.Shared.filterAnyone
            : L10n.Shared.peopleCount(share.permittedUserIds?.count ?? 0)
        var parts = [audience, share.accessMode == .readwrite ? L10n.Shared.canEdit : L10n.Shared.viewOnly]
        if share.hasPassword {
            parts.append(L10n.Shared.statusPassword)
        }
        parts.append(expiry)
        return parts.dropFirst().reduce(parts[0]) { L10n.Shared.statusStep($0, $1) }
    }

    private var expiry: String {
        switch notice {
        case .expired: return L10n.Shared.badgeExpired
        case let .daysLeft(days): return L10n.Shared.daysLeft(days)
        case nil:
            guard let expiresAt = share.expiresAt else { return L10n.Shared.neverExpires }
            let format = DateDisplayFormat(rawValue: dateFormatRaw) ?? .system
            return L10n.Shared.expiresUntil(format.string(from: expiresAt))
        }
    }
}

#Preview("List: two shares") {
    sharedDetailPreview(.byMe, "personal:Work/Team Roadmap")
}

#Preview("List: live and expired, dark") {
    sharedDetailPreview(
        .byMe,
        "personal:Clients/Northwind Traders International/Proposals and Contracts/2027/Quarterly financial statements and board presentation final v3.pdf"
    )
    .preferredColorScheme(.dark)
}

#Preview("List: deleting one") {
    sharedDetailPreview(.byMe, "personal:Work/Team Roadmap") { $0.deletingIDs = ["s6"] }
}

#Preview("List: one recipient and an unresolved one") {
    sharedDetailPreview(.byMe, "personal:Documents/Bills/Electricity") { state in
        for (id, users) in [("p1", ["u6"]), ("p2", ["u99"])] {
            let base = Share.previewCard(target: .users)
            state.byMe.append(Share(
                id: id, shareToken: base.shareToken, ownerId: base.ownerId, sourcePath: base.sourcePath,
                sourceSpace: "personal", isDirectory: true, accessMode: .readonly, sharingType: .users,
                hasPassword: false, permittedUserIds: users, createdAt: Date(), updatedAt: Date()
            ))
        }
    }
}
