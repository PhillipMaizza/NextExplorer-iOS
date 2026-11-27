#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let tileSize: CGFloat = .size36
        static let tileRadius: CGFloat = .radiusSmall
        static let tileGlyph: CGFloat = .iconSmall
        static let tileFillOpacity: Double = .opacityWash
        static let headerSpacing: CGFloat = .space8
        static let markSize: CGFloat = .size16
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
                                .buttonStyle(.macDS(.secondary, size: .small))
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
                        MacIconButton(
                            IconKit.macCopy,
                            label: L10n.Shared.copyLink,
                            size: .compact,
                            tint: .secondaryDS
                        ) { PlatformPasteboard.copy(share.shareLink(serverURL: serverURL)) }
                    }
                    .padding(.horizontal, .space16)
                    .padding(.vertical, .space12)
                    .macGroupedRows()
                }
            }
        }

        private func subtitle(for share: Share) -> String {
            var parts = [share.accessChoice.title]
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
        var onEdit: (() -> Void)?

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
                    VStack(alignment: .trailing, spacing: .space12) {
                        permissionsGrid
                        Text(modeText)
                            .type(.caption(.semibold), style: .secondary)
                            .monospaced()
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, .space12)
                }
            }
        }

        private var permissionsGrid: some View {
            Grid(horizontalSpacing: .zero, verticalSpacing: .zero) {
                GridRow {
                    Color.clear
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                        .gridColumnAlignment(.leading)
                    ForEach(PermissionRight.allCases, id: \.self) { right in
                        gridCell {
                            Text(right.macTitle(isDirectory: isDirectory)).type(.caption(.semibold), style: .secondary)
                        }
                    }
                }
                ForEach(PermissionScope.allCases, id: \.self) { scope in
                    Rectangle()
                        .fill(Color.macLine)
                        .frame(height: .borderWidthHairline)
                        .gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        Text(scope.macTitle)
                            .type(.body3(.regular))
                            .padding(.trailing, .space8)
                        ForEach(PermissionRight.allCases, id: \.self) { right in
                            gridCell {
                                mark(permissions.can(scope, right))
                            }
                            .accessibilityLabel(L10n.Common.pair(
                                scope.macTitle,
                                right.macTitle(isDirectory: isDirectory)
                            ))
                            .accessibilityHidden(!permissions.can(scope, right))
                        }
                    }
                }
            }
        }

        private func gridCell(@ViewBuilder _ content: () -> some View) -> some View {
            content()
                .frame(maxWidth: .infinity)
                .padding(.vertical, .space8)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.macLine)
                        .frame(width: .borderWidthHairline)
                }
        }

        private var modeText: String {
            "\(FilePermissions.symbolicString(from: permissions.grid)) \u{00B7} \(permissions.octalString)"
        }

        private func mark(_ isAllowed: Bool) -> some View {
            Group {
                if isAllowed {
                    IconKit.checkmarkCircleFill
                        .foregroundStyle(Color.accentText)
                } else {
                    IconKit.minus
                        .foregroundStyle(Color.macLine)
                }
            }
            .frame(width: Metrics.markSize, height: Metrics.markSize)
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
