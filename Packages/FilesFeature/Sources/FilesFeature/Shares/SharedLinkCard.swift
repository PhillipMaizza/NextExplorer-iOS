import CoreModels
import DesignSystem
import Localization
import SwiftUI
import UIKit

/// Shared metrics for the two rows that make up one share on the Shared tab. They live in
/// separate `List` rows (header + detail) on purpose: a header row whose height never changes
/// cannot be vertically centered by its list cell, so it stays perfectly fixed while the detail
/// row is inserted/removed with the List's own animation. A single combined row instead lets the
/// cell center the header mid animation, so the title drifts down then up.
enum SharedLinkMetrics {
    static let padding: CGFloat = .space16
    /// Matches the Browse file row's vertical rhythm (`FileRowView`).
    static let headerVerticalPadding: CGFloat = .space16
    /// Plain reveal, no spring overshoot: header holds still, detail row eases in/out.
    static var expand: Animation { .easeInOut(duration: 0.5) }
    static let actionRowSpacing: CGFloat = .space8
    /// One value for both the meta rows and the link-mode row so they read as one list.
    static let rowVerticalPadding: CGFloat = .space8
    static let actionVerticalPadding: CGFloat = .space12
    static let iconSize: CGFloat = .iconMedium
    static let metaIconSize: CGFloat = .iconSmall
    static let chevronSize: CGFloat = .iconXSmall
    static let actionIconSize: CGFloat = .iconSmall
    static let badgeHorizontalPadding: CGFloat = .space8
    static let badgeVerticalPadding: CGFloat = .space2
    /// Recipient chip inner padding — roomier than the expired badge so names breathe.
    static let chipHorizontalPadding: CGFloat = .space12
    static let chipVerticalPadding: CGFloat = .space4
    /// Chip tint strength — the recipient's categorical color at low alpha behind its name.
    static let chipFillOpacity: Double = 0.16
    static let deletingOpacity: Double = 0.4
    /// Expired links mute the info rows — but never the actions, which stay usable
    /// (delete) or at least fully legible.
    static let expiredInfoOpacity: Double = 0.55
}

/// The always-visible top of a share: icon + name + path (+ expired badge) and the chevron. Tap
/// toggles the detail. This is its own list row so its height is constant and it never moves.
struct SharedLinkHeaderRow: View {
    private typealias Metrics = SharedLinkMetrics

    let share: Share
    let serverURL: URL
    let isByMe: Bool
    let isExpired: Bool
    let isDeleting: Bool
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: .space12) {
                shareIcon
                    .frame(width: Metrics.iconSize, height: Metrics.iconSize)

                VStack(alignment: .leading, spacing: .space2) {
                    HStack(spacing: .space8) {
                        Text(share.displayName)
                            .type(.body2(.semibold), style: .primary(for: .label))
                            .lineLimit(1)
                        if isExpired {
                            Text(L10n.Shared.badgeExpired.uppercased())
                                .type(.caption(.semibold), style: .error)
                                .padding(.horizontal, Metrics.badgeHorizontalPadding)
                                .padding(.vertical, Metrics.badgeVerticalPadding)
                                .background(RoundedRectangle(cornerRadius: .radiusXSmall).fill(Color.negative.opacity(0.15)))
                        }
                    }
                    if isByMe, let path = share.sourcePath, !path.isEmpty {
                        Text(path)
                            .type(.body3(.regular), style: .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)

                // Points down when collapsed, flips up when expanded.
                IconKit.chevronDown
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Metrics.chevronSize, height: Metrics.chevronSize)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, Metrics.padding)
            .padding(.vertical, Metrics.headerVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSHapticButtonStyle())
        .opacity(isDeleting ? Metrics.deletingOpacity : 1)
        .disabled(isDeleting)
    }

    /// Folder glyph for directory shares, a real thumbnail for a by-me image share, otherwise
    /// a per-format `FileTypeIcon` keyed off the shared item's own extension — same treatment
    /// the Browse list gives a file row.
    @ViewBuilder
    private var shareIcon: some View {
        if share.isDirectory {
            IconKit.folderFill
                .resizable().scaledToFit()
                .foregroundStyle(Color.accentText)
        } else if let thumbnailPath {
            ThumbnailImage(
                serverURL: serverURL,
                path: thumbnailPath,
                signature: "\(share.updatedAt.timeIntervalSince1970)",
                fallbackIcon: IconKit.document,
                iconTint: Color.secondaryDS
            )
            .frame(width: Metrics.iconSize, height: Metrics.iconSize)
        } else {
            FileTypeIcon(kind: (share.displayName as NSString).pathExtension)
        }
    }

    /// Full server path for a by-me image share — the only case a real thumbnail is
    /// reachable: shared-with-me links carry only the leaf name, and non-image kinds have no
    /// server thumbnail to fetch.
    private var thumbnailPath: String? {
        guard isByMe, let path = share.sourcePath, !path.isEmpty else { return nil }
        let ext = (share.displayName as NSString).pathExtension
        guard FileItem.isImageKind(ext) || FileItem.isRawImageKind(ext) else { return nil }
        return path
    }
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
            if isByMe { ownerBody } else { recipientBody }
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
    /// so nothing here dims or disables on expiry — the header badge is the only signal.
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
                    copy(directLinkString, label: share.isDirectory ? L10n.Shared.copiedFolderZip : L10n.Shared.copiedDirectFile)
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

    /// "With me": read-only — no link, no mode picker, no delete, matching the web
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

    /// "Shared with" — a globe + label for `anyone`; for specific users, the label row plus a
    /// full-width wrapping strip showing every recipient as its own colored chip (a `+N` chip
    /// covers any recipients whose name hasn't resolved yet).
    @ViewBuilder
    private var sharedWithRow: some View {
        VStack(alignment: .leading, spacing: .space8) {
            HStack(alignment: .top, spacing: .space8) {
                (audienceIsAnyone ? IconKit.web : IconKit.people)
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Metrics.metaIconSize, height: Metrics.metaIconSize)
                    .padding(.top, .space2)
                Text(L10n.Shared.metaSharedWith).type(.body2(.regular), style: .primary(for: .label))
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
    @ViewBuilder
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
        if case .anyone = audience { return true }
        return false
    }

    private var linkModeRow: some View {
        HStack(spacing: .space8) {
            IconKit.shareLink
                .resizable().scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .frame(width: Metrics.metaIconSize, height: Metrics.metaIconSize)
            Text(L10n.Shared.linkMode).type(.body2(.regular), style: .primary(for: .label))
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
            Text(label).type(.body2(.regular), style: .primary(for: .label))
            Spacer()
            Text(value)
                .type(.body2(.regular), style: isWarning ? .error : .secondary)
                .multilineTextAlignment(.trailing)
                .truncationMode(.tail)
        }
        .padding(.vertical, Metrics.rowVerticalPadding)
    }

    /// Filled pill for the copy/delete actions. `tint` is `.accent` or `.negative`. Stays
    /// full opacity even when disabled (an expired link's copy buttons) — it just stops
    /// responding; `copy()` guards the action too.
    private func pillAction(_ icon: Image, _ title: String, tint: Color, isEnabled: Bool, action: @escaping () -> Void) -> some View {
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
        .buttonStyle(DSHapticButtonStyle())
        .allowsHitTesting(isEnabled)
    }

    private var expiresText: String {
        guard let expiresAt = share.expiresAt else { return L10n.Common.never }
        return Self.expiryFormatter.string(from: expiresAt)
    }

    private var baseURLString: String {
        if let scheme = serverURL.scheme, let host = serverURL.host {
            let port = serverURL.port.map { ":\($0)" } ?? ""
            return "\(scheme)://\(host)\(port)"
        }
        return serverURL.absoluteString
    }

    private var shareLinkString: String {
        "\(baseURLString)/share/\(share.shareToken)"
    }

    private var directLinkString: String {
        let base = "\(baseURLString)/api/share/\(share.shareToken)/file"
        return directLinkMode == .auto ? base : "\(base)?mode=\(directLinkMode.rawValue)"
    }

    private func copy(_ string: String, label: String) {
        UIPasteboard.general.string = string
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

/// Preview host: composes the header + detail rows in a real inset-grouped List and drives the
/// expansion so the accordion can be exercised, exactly as `SharedSegmentList` does.
private struct SharedLinkCardPreview: View {
    let share: Share
    var isByMe: Bool = true
    var isExpired: Bool = false
    var audience: SharedFeature.State.Audience = .anyone
    var sharedByText: String = ""
    var startExpanded: Bool = false

    @State private var isExpanded = false
    private let url = URL(string: "https://cloud.phillipmaizza.com")!

    var body: some View {
        List {
            Section {
                SharedLinkHeaderRow(
                    share: share, serverURL: url, isByMe: isByMe, isExpired: isExpired,
                    isDeleting: false, isExpanded: isExpanded,
                    onToggle: { withAnimation(SharedLinkMetrics.expand) { isExpanded.toggle() } }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.backgroundSecondary)
                .listRowSeparator(.hidden)
                if isExpanded {
                    SharedLinkDetailRow(
                        share: share, serverURL: url, isByMe: isByMe, isExpired: isExpired,
                        audience: audience, sharedByText: sharedByText, isDeleting: false,
                        onDelete: {}, onEdit: {}, onCopied: { _ in }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.backgroundSecondary)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundPrimary)
        .onAppear { isExpanded = startExpanded }
    }
}

#Preview("Card — collapsed / expanded") {
    SharedLinkCardPreview(share: .previewCard(isDirectory: true))
}

#Preview("Card — users") {
    SharedLinkCardPreview(
        share: .previewCard(target: .users),
        audience: .users(names: ["Jamie Rivera", "Sam Okafor", "Jeremy Brown", "Dana Lee"], unnamed: 1),
        startExpanded: true
    )
}

#Preview("Card — expiry") {
    SharedLinkCardPreview(share: .previewCard(expiresAt: Date().addingTimeInterval(86_400 * 3)), startExpanded: true)
}

#Preview("Card — expired") {
    SharedLinkCardPreview(share: .previewCard(expiresAt: Date().addingTimeInterval(-3600)), isExpired: true, startExpanded: true)
}

#Preview("Card — with me") {
    SharedLinkCardPreview(share: .previewCard(sourcePath: nil), isByMe: false, sharedByText: "Alex Kim", startExpanded: true)
}
