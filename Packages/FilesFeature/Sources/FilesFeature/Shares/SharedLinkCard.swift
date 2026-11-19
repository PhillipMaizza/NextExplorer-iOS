import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// Metrics for a share's detail row on the Shared tab. It is its own `List` row below the item
/// row on purpose: a row whose height never changes cannot be vertically centered by its cell,
/// so the item row stays fixed while the details are inserted and removed.
enum SharedLinkMetrics {
    static let padding: CGFloat = .space16
    /// Plain reveal, no spring overshoot: the item row holds still, details ease in and out.
    static var expand: Animation {
        DSMotion.cardExpand
    }

    static let actionRowSpacing: CGFloat = .space8
    /// One value for both the meta rows and the link-mode row so they read as one list.
    static let rowVerticalPadding: CGFloat = .space8
    static let actionVerticalPadding: CGFloat = .space12
    static let metaIconSize: CGFloat = .iconSmall
    static let actionIconSize: CGFloat = .iconSmall
    static let badgeHorizontalPadding: CGFloat = .space8
    static let badgeVerticalPadding: CGFloat = .space2
    /// Recipient chip inner padding: roomier than the expired badge so names breathe.
    static let chipHorizontalPadding: CGFloat = .space12
    static let chipVerticalPadding: CGFloat = .space4
    /// Chip tint strength: the recipient's categorical color at low alpha behind its name.
    static let chipFillOpacity: Double = 0.16
    static let deletingOpacity: Double = 0.4
    /// Expired links mute the info rows: but never the actions, which stay usable
    /// (delete) or at least fully legible.
    static let expiredInfoOpacity: Double = 0.55
}

/// The expanded metadata for a share: shared-with / access / expiration, the direct-link mode
/// picker, and the per-link actions ("by me"); or just who shared it, access and expiry ("with
/// me"). Rendered as its own list row so it inserts/removes cleanly below the fixed header.
struct SharedLinkDetailRow: View {
    private typealias Metrics = SharedLinkMetrics

    let share: Share
    let serverURL: URL
    let isByMe: Bool
    let isExpired: Bool
    let audience: SharedFeature.State.Audience
    let sharedByText: String
    let isDeleting: Bool
    let onDelete: () -> Void
    let onEdit: () -> Void
    let onCopied: (String) -> Void

    @State private var directLinkMode: DirectLinkMode = .auto

    var body: some View {
        Group {
            if isByMe {
                ownerBody
            } else {
                recipientBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isDeleting ? Metrics.deletingOpacity : 1)
        .disabled(isDeleting)
    }

    private var accessIcon: Image {
        share.accessMode == .readonly ? IconKit.lock : IconKit.lockOpen
    }

    /// "By me": full metadata + the direct-link mode picker + copy/delete actions. Web keeps
    /// expired shares fully usable for the owner (the link just stops working server-side),
    /// so nothing here dims or disables on expiry: the header badge is the only signal.
    private var ownerBody: some View {
        VStack(alignment: .leading, spacing: .space8) {
            sharedWithRow
            metaRow(accessIcon, L10n.Shared.metaAccess, share.accessMode.title)
            metaRow(IconKit.calendar, L10n.Shared.metaExpiration, expiresText, isWarning: isExpired)
            linkModeRow

            HStack(spacing: Metrics.actionRowSpacing) {
                pillAction(IconKit.link, L10n.Shared.actionShareLink, tint: .accent, isEnabled: true) {
                    copy(shareLinkString, label: L10n.Shared.copiedShareLink)
                }
                pillAction(
                    IconKit.copy,
                    share.isDirectory ? L10n.Shared.actionFolderLink : L10n.Shared.actionFileLink,
                    tint: .accent,
                    isEnabled: true
                ) {
                    copy(
                        directLinkString,
                        label: share.isDirectory ? L10n.Shared.copiedFolderZip : L10n.Shared.copiedDirectFile
                    )
                }
            }

            HStack(spacing: Metrics.actionRowSpacing) {
                pillAction(IconKit.rename, L10n.Common.edit, tint: .accent, isEnabled: true, action: onEdit)
                pillAction(IconKit.delete, L10n.Common.delete, tint: .negative, isEnabled: true, action: onDelete)
            }
            .padding(.top, Metrics.actionRowSpacing)
        }
        .padding(.horizontal, Metrics.padding)
        .padding(.bottom, Metrics.padding)
    }

    /// "With me": read-only; no link, no mode picker, no delete, matching the web
    /// `SharedWithMeView`. Just who shared it, the access level, and the expiry.
    private var recipientBody: some View {
        VStack(alignment: .leading, spacing: .space8) {
            metaRow(IconKit.person, L10n.Shared.metaSharedBy, sharedByText)
            metaRow(accessIcon, L10n.Shared.metaAccess, share.accessMode.title)
            metaRow(IconKit.calendar, L10n.Shared.metaExpiration, expiresText, isWarning: isExpired)
        }
        .opacity(isExpired ? Metrics.expiredInfoOpacity : 1)
        .padding(.horizontal, Metrics.padding)
        .padding(.bottom, Metrics.padding)
    }

    /// "Shared with": a globe + label for `anyone`; for specific users, the label row plus a
    /// full-width wrapping strip showing every recipient as its own colored chip (a `+N` chip
    /// covers any recipients whose name hasn't resolved yet).
    private var sharedWithRow: some View {
        VStack(alignment: .leading, spacing: .space8) {
            HStack(alignment: .top, spacing: .space8) {
                (audienceIsAnyone ? IconKit.web : IconKit.people)
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Metrics.metaIconSize, height: Metrics.metaIconSize)
                    .padding(.top, .space2)
                Text(L10n.Shared.metaSharedWith).type(.body2(.regular), style: .primaryOnSurface)
                Spacer(minLength: .space8)
                if audienceIsAnyone {
                    Text(L10n.Shared.anyoneWithLink).type(.body2(.regular), style: .secondary)
                }
            }
            if case let .users(names, unnamed) = audience {
                recipientChips(names: names, unnamed: unnamed)
            }
        }
        .padding(.vertical, Metrics.rowVerticalPadding)
    }

    /// Every recipient as its own chip, each in a stable per-name color, laid out on a single
    /// horizontal row that scrolls when the names overflow. Any recipients whose display name
    /// hasn't loaded collapse into a trailing neutral `+N`.
    private func recipientChips(names: [String], unnamed: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .space4) {
                ForEach(names, id: \.self) { name in
                    Text(name)
                        .type(.body3(.semibold))
                        .foregroundStyle(Color.categorical(for: name))
                        .lineLimit(1)
                        .padding(.horizontal, Metrics.chipHorizontalPadding)
                        .padding(.vertical, Metrics.chipVerticalPadding)
                        .background(Capsule().fill(Color.categorical(for: name).opacity(Metrics.chipFillOpacity)))
                }
                if unnamed > 0 {
                    Text(L10n.Shared.moreRecipients(unnamed))
                        .type(.body3(.semibold), style: .secondary)
                        .padding(.horizontal, Metrics.chipHorizontalPadding)
                        .padding(.vertical, Metrics.chipVerticalPadding)
                        .background(Capsule().fill(Color.secondaryDS.opacity(Metrics.chipFillOpacity)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var audienceIsAnyone: Bool {
        if case .anyone = audience {
            return true
        }
        return false
    }

    private var linkModeRow: some View {
        HStack(spacing: .space8) {
            IconKit.shareLink
                .resizable().scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .frame(width: Metrics.metaIconSize, height: Metrics.metaIconSize)
            Text(L10n.Shared.linkMode).type(.body2(.regular), style: .primaryOnSurface)
            Spacer()
            Picker(L10n.Shared.linkMode, selection: $directLinkMode) {
                ForEach(DirectLinkMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Color.secondaryDS)
        }
        .padding(.vertical, Metrics.rowVerticalPadding)
    }

    /// Same font/padding as `linkModeRow` so the whole expanded block reads as one list.
    private func metaRow(_ icon: Image, _ label: String, _ value: String, isWarning: Bool = false) -> some View {
        HStack(spacing: .space8) {
            icon
                .resizable().scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .frame(width: Metrics.metaIconSize, height: Metrics.metaIconSize)
            Text(label).type(.body2(.regular), style: .primaryOnSurface)
            Spacer()
            Text(value)
                .type(.body2(.regular), style: isWarning ? .error : .secondary)
                .multilineTextAlignment(.trailing)
                .truncationMode(.tail)
        }
        .padding(.vertical, Metrics.rowVerticalPadding)
    }

    /// Filled pill for the copy/delete actions. `tint` is `.accent` or `.negative`. Stays
    /// full opacity even when disabled (an expired link's copy buttons): it just stops
    /// responding; `copy()` guards the action too.
    private func pillAction(
        _ icon: Image,
        _ title: String,
        tint: Color,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: .space8) {
                icon
                    .resizable().scaledToFit()
                    .frame(width: Metrics.actionIconSize, height: Metrics.actionIconSize)
                Text(title).type(.body3(.semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Metrics.actionVerticalPadding)
            .background(RoundedRectangle(cornerRadius: .radiusControl).fill(tint.opacity(0.12)))
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressableButtonStyle())
        .allowsHitTesting(isEnabled)
    }

    private var expiresText: String {
        guard let expiresAt = share.expiresAt else { return L10n.Common.never }
        return Self.expiryFormatter.string(from: expiresAt)
    }

    private var shareLinkString: String {
        share.shareLink(serverURL: serverURL)
    }

    private var directLinkString: String {
        share.directLink(serverURL: serverURL, mode: directLinkMode)
    }

    private func copy(_ string: String, label: String) {
        PlatformPasteboard.copy(string)
        onCopied(label)
    }

    private static let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

extension Share {
    static func previewCard(
        isDirectory: Bool = false,
        target: ShareTarget = .anyone,
        hasPassword: Bool = false,
        expiresAt: Date? = nil,
        sourcePath: String? = "Documents/Bills/Electricity"
    ) -> Share {
        Share(
            id: UUID().uuidString, shareToken: "UrkLIGIHMF", ownerId: "me",
            sourcePath: sourcePath, sourceName: sourcePath == nil ? "Team Roadmap" : nil,
            isDirectory: isDirectory, accessMode: .readonly, sharingType: target,
            hasPassword: hasPassword, expiresAt: expiresAt, label: sourcePath == nil ? "Team Roadmap" : "Electricity",
            createdAt: Date(), updatedAt: Date()
        )
    }
}

/// Preview host: the detail row in a real inset grouped List, as `SharedSegmentList` shows it.
private struct SharedLinkCardPreview: View {
    let share: Share
    var isByMe: Bool = true
    var isExpired: Bool = false
    var audience: SharedFeature.State.Audience = .anyone
    var sharedByText: String = ""

    private let url = URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")

    var body: some View {
        DSGroupedList {
            Section {
                SharedLinkDetailRow(
                    share: share,
                    serverURL: url,
                    isByMe: isByMe,
                    isExpired: isExpired,
                    audience: audience,
                    sharedByText: sharedByText,
                    isDeleting: false,
                    onDelete: {},
                    onEdit: {},
                    onCopied: { _ in }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.backgroundSecondary)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundPrimary)
    }
}

#Preview("Card: folder") {
    SharedLinkCardPreview(share: .previewCard(isDirectory: true))
}

#Preview("Card: users") {
    SharedLinkCardPreview(
        share: .previewCard(target: .users),
        audience: .users(names: ["Jamie Rivera", "Sam Okafor", "Jeremy Brown", "Dana Lee"], unnamed: 1)
    )
}

#Preview("Card: expiry") {
    SharedLinkCardPreview(share: .previewCard(expiresAt: Date().addingTimeInterval(86_400 * 3)))
}

#Preview("Card: expired") {
    SharedLinkCardPreview(
        share: .previewCard(expiresAt: Date().addingTimeInterval(-3600)),
        isExpired: true
    )
}

#Preview("Card: with me") {
    SharedLinkCardPreview(
        share: .previewCard(sourcePath: nil),
        isByMe: false,
        sharedByText: "Alex Kim"
    )
}
