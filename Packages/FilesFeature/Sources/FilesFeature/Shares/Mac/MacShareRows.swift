#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let avatarSize: CGFloat = 26
        static let personRowHeight: CGFloat = 42
        static let anyoneTint = Color.categoricalPalette[0]
        static let anyoneIconSize: CGFloat = 34
        static let valueMinimumScale: CGFloat = 0.8
        static let anyoneTintOpacity: Double = 0.15
    }

    struct MacShareAnyoneRow: View {
        var onLimit: (() -> Void)?

        var body: some View {
            HStack(spacing: .space12) {
                IconKit.web
                    .foregroundStyle(Metrics.anyoneTint)
                    .frame(width: Metrics.anyoneIconSize, height: Metrics.anyoneIconSize)
                    .background(
                        Metrics.anyoneTint.opacity(Metrics.anyoneTintOpacity),
                        in: RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: .space2) {
                    Text(L10n.ShareTarget.anyone)
                        .type(.body3(.semibold))
                    Text(L10n.Shared.noAccountNeeded)
                        .type(.caption(.regular), style: .secondary)
                }
                .lineLimit(1)
                Spacer(minLength: .space8)
                if let onLimit {
                    Button(L10n.Shared.limit, action: onLimit)
                        .buttonStyle(.plain)
                        .type(.body3(.semibold))
                        .foregroundStyle(Color.accentText)
                }
            }
            .padding(.vertical, .space8)
            .frame(minHeight: MacInspectorMetrics.rowHeight)
        }
    }

    struct MacShareStatTile: View {
        let value: String
        let label: String

        var body: some View {
            VStack(alignment: .leading, spacing: .space2) {
                Text(value)
                    .type(.headline4)
                    .lineLimit(1)
                    .minimumScaleFactor(Metrics.valueMinimumScale)
                Text(label)
                    .type(.caption(.regular), style: .secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, .space8)
            .frame(maxWidth: .infinity, minHeight: MacInspectorMetrics.tileHeight, alignment: .leading)
            .padding(.horizontal, .space12)
            .macGroupedRows()
            .accessibilityElement(children: .combine)
        }
    }

    struct MacSharePersonLabel: View {
        let name: String
        let email: String?
        let avatarSize: CGFloat
        var nameType = Typography.TextType.body3(.regular)
        var nameLineLimit = 1

        var body: some View {
            HStack(spacing: .space8) {
                AvatarView.person(name, size: avatarSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: .zero) {
                    Text(name)
                        .type(nameType)
                        .lineLimit(nameLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                    if let email {
                        Text(email)
                            .type(.caption(.regular), style: .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    struct MacSharePersonRow: View {
        let name: String
        let email: String?

        var body: some View {
            HStack(spacing: .zero) {
                MacSharePersonLabel(name: name, email: email, avatarSize: Metrics.avatarSize)
                    .textSelection(.enabled)
                Spacer(minLength: .zero)
            }
            .padding(.vertical, .space8)
            .frame(minHeight: Metrics.personRowHeight)
        }
    }

    struct MacInspectorControlRow<Control: View>: View {
        let label: String
        @ViewBuilder let control: () -> Control

        var body: some View {
            HStack(spacing: .space12) {
                Text(label)
                    .type(.body3(.regular), style: .secondary)
                    .fixedSize()
                Spacer(minLength: .space8)
                control()
            }
            .frame(minHeight: MacInspectorMetrics.rowHeight)
        }
    }

    #Preview("Stat tiles and rows") {
        let facts = SharedShareFacts(share: Share.previewSharedByMe[0], notice: nil, dateFormat: .system)
        let user = Share.previewShareableUsers[0]
        VStack(alignment: .leading, spacing: .space16) {
            HStack(alignment: .top, spacing: .space8) {
                MacShareStatTile(value: facts.downloads, label: L10n.Shared.metaDownloads)
                MacShareStatTile(value: facts.lastOpenedShort, label: L10n.Shared.metaLastOpened)
                MacShareStatTile(value: facts.created, label: L10n.Shared.metaShared)
            }
            MacInspectorGroup {
                MacSharePersonRow(name: user.displayLabel, email: user.email)
                MacSharePersonRow(name: user.username, email: nil)
            }
            MacInspectorGroup {
                MacShareAnyoneRow {}
            }
        }
        .padding(MacInspectorMetrics.padding)
        .frame(width: MacInspectorMetrics.width)
        .background(Color.macCard)
    }
#endif
