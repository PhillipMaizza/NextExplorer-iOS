#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let tileSize: CGFloat = 34
        static let tileRadius: CGFloat = 10
        static let tileGlyph: CGFloat = .iconSmall
        static let tileFillOpacity: Double = 0.17
        static let headerSpacing: CGFloat = 10
    }

    struct MacInspectorTile: View {
        let icon: Image
        var tint = Color.secondaryDS
        var fill = Color.macSegment

        var body: some View {
            RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                .fill(fill)
                .overlay {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: Metrics.tileGlyph, height: Metrics.tileGlyph)
                        .foregroundStyle(tint)
                }
                .frame(width: Metrics.tileSize, height: Metrics.tileSize)
                .accessibilityHidden(true)
        }
    }

    struct MacInspectorSharingSection: View {
        let shares: [Share]
        let serverURL: URL
        var onShare: (() -> Void)?

        var body: some View {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                MacInspectorSectionHeader(
                    title: L10n.FileInfo.sectionSharing,
                    count: shares.isEmpty ? nil : shares.count,
                    actionTitle: shares.isEmpty ? nil : L10n.FileInfo.newLink,
                    action: onShare
                )
                if shares.isEmpty {
                    HStack(spacing: .space12) {
                        MacInspectorTile(icon: IconKit.link)
                        Text(L10n.FileInfo.notShared).type(.body3(.regular), style: .secondary)
                        Spacer(minLength: .zero)
                        if let onShare {
                            Button(L10n.FileInfo.createLink, action: onShare)
                                .buttonStyle(.macDS(.primary, size: .small))
                        }
                    }
                    .padding(.horizontal, .space16)
                    .padding(.vertical, .space12)
                    .macGroupedRows()
                }
                ForEach(shares) { share in
                    HStack(spacing: .space12) {
                        MacInspectorTile(
                            icon: IconKit.link,
                            tint: Color.accentText,
                            fill: Color.accent.opacity(Metrics.tileFillOpacity)
                        )
                        VStack(alignment: .leading, spacing: .space2) {
                            Text(share.label ?? share.displayName).type(.body3(.regular)).lineLimit(1)
                            Text(subtitle(for: share)).type(.caption(.regular), style: .secondary).lineLimit(1)
                        }
                        Spacer(minLength: .zero)
                        Button { PlatformPasteboard.copy(share.shareLink(serverURL: serverURL)) } label: {
                            IconKit.copy.foregroundStyle(Color.secondaryDS)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabelWithTooltip(L10n.Shared.copyLink)
                    }
                    .padding(.horizontal, .space16)
                    .padding(.vertical, .space12)
                    .macGroupedRows()
                }
            }
        }

        private func subtitle(for share: Share) -> String {
            var parts = [share.accessMode.title]
            if let expiresAt = share.expiresAt {
                parts.append(expiresAt <= Date()
                    ? L10n.Shared.badgeExpired
                    : expiresAt.formatted(date: .abbreviated, time: .omitted))
            }
            return parts.joined(separator: " \u{00B7} ")
        }
    }

    struct MacInspectorPermissionsSection: View {
        let permissions: FilePermissions
        let isDirectory: Bool
        let onEdit: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                MacInspectorSectionHeader(
                    title: L10n.Permissions.title,
                    actionTitle: L10n.ellipsized(L10n.Common.edit),
                    action: onEdit
                )
                MacInspectorGroup {
                    MacInspectorRow(L10n.Permissions.fieldOwner, permissions.owner)
                    MacInspectorRow(L10n.Permissions.fieldGroup, permissions.group)
                }
                Grid(horizontalSpacing: .space8, verticalSpacing: .space8) {
                    GridRow {
                        Text(modeText)
                            .type(.caption(.semibold), style: .secondary)
                            .monospaced()
                            .lineLimit(1)
                            .fixedSize()
                            .gridColumnAlignment(.leading)
                        ForEach(PermissionRight.allCases, id: \.self) { right in
                            Text(right.macTitle(isDirectory: isDirectory)).type(.caption(.semibold), style: .secondary)
                        }
                    }
                    ForEach(PermissionScope.allCases, id: \.self) { scope in
                        GridRow {
                            Text(scope.macTitle).type(.body3(.regular))
                            ForEach(PermissionRight.allCases, id: \.self) { right in
                                mark(permissions.can(scope, right))
                                    .frame(maxWidth: .infinity)
                                    .accessibilityLabel(L10n.Common.pair(
                                        scope.macTitle,
                                        right.macTitle(isDirectory: isDirectory)
                                    ))
                                    .accessibilityHidden(!permissions.can(scope, right))
                            }
                        }
                    }
                }
                .padding(.horizontal, .space16)
                .padding(.vertical, .space12)
                .macGroupedRows()
            }
        }

        private var modeText: String {
            "\(FilePermissions.symbolicString(from: permissions.grid)) \u{00B7} \(permissions.octalString)"
        }

        @ViewBuilder
        private func mark(_ isAllowed: Bool) -> some View {
            if isAllowed {
                IconKit.checkmark
                    .fontWeight(.bold)
                    .foregroundStyle(Color.accentText)
            } else {
                IconKit.minus
                    .foregroundStyle(Color.macLine)
            }
        }
    }

    #Preview("Sharing") {
        MacInspectorSharingSection(
            shares: [.previewCard(), .previewCard(target: .users, hasPassword: true)],
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            onShare: {}
        )
        .padding(MacInspectorMetrics.padding)
        .frame(width: MacInspectorMetrics.width)
        .background(Color.macCard)
    }

    #Preview("Not shared") {
        MacInspectorSharingSection(
            shares: [],
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            onShare: {}
        )
        .padding(MacInspectorMetrics.padding)
        .frame(width: MacInspectorMetrics.width)
        .background(Color.macCard)
    }
#endif
