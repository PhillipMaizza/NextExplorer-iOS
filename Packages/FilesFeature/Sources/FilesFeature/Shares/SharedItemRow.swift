import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let iconSize: CGFloat = 36
    static let folderGlyphSize: CGFloat = 30
    static var dividerInset: CGFloat {
        .space16 + iconSize + .space12
    }

    static let sharerAvatarSize: CGFloat = 20
    static let expiredOpacity: Double = 0.45
    static let deletingOpacity: Double = 0.4
}

/// One shared file or folder on the Shared list: icon, name and parent folder, who each share
/// reaches in the top right corner (By me) or the sharer under the name (With me), and the
/// nearest countdown on its own line. Fully expired items fade. Tap opens the item sheet.
struct SharedItemRow: View {
    let item: SharedFeature.Item
    let serverURL: URL
    let isByMe: Bool
    let isDeleting: Bool
    /// A hairline above the row, inset to the text, between items.
    var shouldShowDivider = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: .space12) {
                SharedItemIcon(share: item.shares[0], name: item.name, serverURL: serverURL, isByMe: isByMe)
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
                    .opacity(item.isExpired ? Constants.expiredOpacity : 1)

                VStack(alignment: .leading, spacing: .space4) {
                    HStack(alignment: .top, spacing: .space8) {
                        Text(item.name)
                            .type(.body2(.semibold), style: .primaryOnSurface)
                            .lineLimit(2)
                            .opacity(item.isExpired ? Constants.expiredOpacity : 1)
                        Spacer(minLength: .space4)
                        if isByMe {
                            SharedAudienceBadgeRow(badges: item.badges)
                        }
                    }
                    locationText
                    if !isByMe, let sharer = item.badges.first?.people.first {
                        AvatarView(
                            displayName: sharer.name,
                            size: Constants.sharerAvatarSize,
                            tint: Color.categorical(for: sharer.name)
                        )
                        .opacity(item.isExpired ? Constants.expiredOpacity : 1)
                        .accessibilityLabel(sharer.name)
                    }
                    if let daysLeft {
                        Text(L10n.Shared.daysLeft(daysLeft))
                            .type(.caption(.semibold), style: .warning)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, .space16)
            .padding(.vertical, .space16)
            .overlay(alignment: .top) {
                if shouldShowDivider {
                    Divider().padding(.leading, Constants.dividerInset)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressableButtonStyle())
        .opacity(isDeleting ? Constants.deletingOpacity : 1)
        .disabled(isDeleting)
    }

    @ViewBuilder
    private var locationText: some View {
        if let location = item.location {
            Text(PathTrail.text(location))
                .type(.body3(.regular), style: .secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
    }

    /// The soonest countdown among the shares still live.
    private var daysLeft: Int? {
        item.badges.compactMap { badge -> Int? in
            if case let .daysLeft(days) = badge.expiry {
                return days
            }
            return nil
        }
        .min()
    }
}

/// Folder glyph, a real thumbnail for a By me image, otherwise the per format type icon.
struct SharedItemIcon: View {
    let share: Share
    let name: String
    let serverURL: URL
    let isByMe: Bool
    var folderGlyphSize: CGFloat = Constants.folderGlyphSize

    var body: some View {
        if share.isDirectory {
            IconKit.folderFill
                .resizable().scaledToFit()
                .foregroundStyle(Color.accentText)
                .frame(width: folderGlyphSize, height: folderGlyphSize)
        } else if let thumbnailPath {
            ThumbnailImage(
                serverURL: serverURL,
                path: thumbnailPath,
                signature: "\(share.updatedAt.timeIntervalSince1970)",
                fallbackIcon: IconKit.document,
                fallbackKind: kind,
                iconTint: Color.secondaryDS
            )
            .clipShape(RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous))
        } else {
            FileTypeIcon(kind: kind)
        }
    }

    private var kind: String {
        (name as NSString).pathExtension
    }

    /// Only By me carries the full path, and only images have a server thumbnail.
    private var thumbnailPath: String? {
        guard isByMe, let path = share.sourcePath, !path.isEmpty,
              FileItem.isImageKind(kind) || FileItem.isRawImageKind(kind) else { return nil }
        return path
    }
}

@MainActor
private func itemRowsPreview(segment: SharedFeature.Segment) -> some View {
    let state = sharedPreviewState()
    let items = state.items(for: segment)
    return ScrollView {
        VStack(spacing: 0) {
            ForEach(items) { item in
                SharedItemRow(
                    item: item,
                    serverURL: state.serverURL,
                    isByMe: segment == .byMe,
                    isDeleting: false,
                    onTap: {}
                )
                Divider()
            }
        }
        .background(Color.backgroundSecondary)
    }
    .background(Color.backgroundPrimary)
}

#Preview("Rows: By me") {
    itemRowsPreview(segment: .byMe)
}

#Preview("Rows: By me, dark") {
    itemRowsPreview(segment: .byMe)
        .preferredColorScheme(.dark)
}

#Preview("Rows: With me") {
    itemRowsPreview(segment: .withMe)
}
