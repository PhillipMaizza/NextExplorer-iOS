#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let bubble: CGFloat = 28
        static let collapsedLimit = 4
        static let shape = RoundedRectangle(cornerRadius: .radiusMedium, style: .continuous)
    }

    private struct RowBubble: View {
        let icon: Image

        var body: some View {
            icon
                .foregroundStyle(Color.macChromeSecondary)
                .frame(width: Metrics.bubble, height: Metrics.bubble)
                .background(Circle().fill(Color.macSegment))
                .accessibilityHidden(true)
        }
    }

    private struct RowText: View {
        let title: String
        let detail: String

        var body: some View {
            VStack(alignment: .leading, spacing: .space2) {
                Text(title)
                    .type(.body3(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .type(.caption(.regular), style: .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    struct MacShareAudienceRow: View {
        let target: ShareTarget
        let recipients: [User]

        @State private var isShowingAll = false

        private var hiddenCount: Int {
            isShowingAll ? .zero : max(recipients.count - Metrics.collapsedLimit, .zero)
        }

        var body: some View {
            if target == .users, !recipients.isEmpty {
                DSFlowLayout(horizontalSpacing: .space8, verticalSpacing: .space8) {
                    ForEach(recipients.prefix(recipients.count - hiddenCount)) { pill($0).macDialogPop() }
                    if recipients.count > Metrics.collapsedLimit {
                        toggle
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.space12)
                .background(Metrics.shape.fill(Color.macRow))
            } else {
                HStack(spacing: .space12) {
                    RowBubble(icon: target.icon)
                    RowText(
                        title: target.title,
                        detail: target == .anyone ? L10n.Shared.noAccountNeeded : L10n.CreateShare.summarySpecificPeople
                    )
                }
                .padding(.horizontal, .space16)
                .padding(.vertical, .space12)
                .background(Metrics.shape.fill(Color.macRow))
            }
        }

        private var toggle: some View {
            Button {
                withAnimation(DSMotion.controlMorph) { isShowingAll.toggle() }
            } label: {
                HStack(spacing: .space4) {
                    if hiddenCount > 0 {
                        Text(L10n.Shared.moreRecipients(hiddenCount)).type(.body3(.semibold))
                    }
                    Text(isShowingAll ? L10n.Shared.showLess : L10n.Shared.showMore)
                        .type(.body3(.regular), style: .secondary)
                }
                .padding(.horizontal, .space12)
                .frame(minHeight: Metrics.bubble)
                .padding(.vertical, .space4)
                .background(Capsule().strokeBorder(Color.macLine, lineWidth: .borderWidthHairline))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }

        private func pill(_ user: User) -> some View {
            MacSharePersonLabel(
                name: user.displayLabel,
                email: user.email,
                avatarSize: Metrics.bubble,
                nameType: .body3(.semibold)
            )
            .padding(.leading, .space4)
            .padding(.trailing, .space12)
            .padding(.vertical, .space4)
            .background(Capsule().fill(Color.macSegment))
        }
    }

    struct MacShareDirectLinkRow: View {
        let share: Share
        let link: URL
        @Binding var mode: DirectLinkMode

        private var choices: [DirectLinkChoice] {
            share.directLinkChoices
        }

        var body: some View {
            if let choice = choices.first(where: { $0.mode == mode }) ?? choices.first {
                VStack(alignment: .leading, spacing: .space8) {
                    if choices.count > 1 {
                        MacSegmentedPicker(
                            L10n.CreateShare.directLinkMode,
                            options: choices,
                            selection: Binding(get: { choice }, set: { mode = $0.mode }),
                            isFullWidth: true,
                            label: \.title
                        )
                    }
                    ZStack {
                        MacCopyBox(link.absoluteString, icon: share.isDirectory ? IconKit.folder : IconKit.document)
                            .id(link)
                            .transition(.opacity)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: .space4) {
                        IconKit.info
                            .imageScale(.small)
                            .accessibilityHidden(true)
                        Text(choice.detail)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.opacity)
                    }
                    .type(.caption(.regular), style: .secondary)
                }
                .animation(DSMotion.stateFade, value: mode)
            }
        }
    }

    struct MacShareSettingsChips: View {
        let share: Share

        var body: some View {
            HStack(spacing: .space8) {
                MacIconChip(icon: share.accessChoice.icon, tone: .gray, help: share.accessChoice.title)
                if share.hasPassword {
                    MacIconChip(icon: IconKit.macLock, tone: .amber, help: L10n.Common.password)
                }
                if let expiresAt = share.expiresAt {
                    let date = expiresAt.formatted(date: .abbreviated, time: time(for: expiresAt))
                    MacChip(text: date, tone: .amber, icon: IconKit.macCalendar)
                        .help(L10n.ApiTokens.expires(date))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func time(for date: Date) -> Date.FormatStyle.TimeStyle {
            Calendar.current.isDateInToday(date) ? .shortened : .omitted
        }
    }

    #Preview("Audience rows") {
        VStack(spacing: .space16) {
            MacShareAudienceRow(target: .anyone, recipients: [])
            MacShareAudienceRow(target: .users, recipients: Array(Share.previewShareableUsers.prefix(1)))
            MacShareAudienceRow(target: .users, recipients: Share.previewShareableUsers)
        }
        .padding(MacInspectorMetrics.padding)
        .frame(width: MacFormSheetMetrics.width)
        .background(Color.macCard)
    }

    #Preview("Settings chips") {
        VStack(alignment: .leading, spacing: .space16) {
            MacShareSettingsChips(share: .previewCard())
            MacShareSettingsChips(share: .previewCard(hasPassword: true))
            MacShareSettingsChips(share: .previewCard(
                hasPassword: true,
                expiresAt: Date().addingTimeInterval(86_400 * 7)
            ))
        }
        .padding(MacInspectorMetrics.padding)
        .frame(width: MacFormSheetMetrics.width)
        .background(Color.macCard)
    }

    #Preview("Direct link row") {
        MacShareDirectLinkRow(
            share: Share.previewSharedByMe[0],
            link: sharedPreviewServerURL,
            mode: .constant(.auto)
        )
        .padding(MacInspectorMetrics.padding)
        .frame(width: MacFormSheetMetrics.width)
        .background(Color.macCard)
    }
#endif
