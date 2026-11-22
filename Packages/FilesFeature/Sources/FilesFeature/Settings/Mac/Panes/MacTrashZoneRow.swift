#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    struct MacTrashZoneRow: View {
        let zone: TrashZone
        let problems: Int
        @State private var isExpanded = false

        private var counts: String {
            ServerSettingsMetrics.joined([
                L10n.TrashSettings.zoneItems(zone.itemCount, TrashSettingsView.bytes(zone.usedBytes)),
                L10n.TrashSettings.zoneVersions(zone.versionCount, TrashSettingsView.bytes(zone.versionBytes)),
            ])
        }

        private var info: [String] {
            let usage = zone.isAvailable
                ? [
                    L10n.TrashSettings.usage(
                        TrashSettingsView.bytes(zone.heldBytes),
                        zone.budgetBytes.map(TrashSettingsView.bytes) ?? L10n.TrashSettings.noBudget
                    ),
                    L10n.TrashSettings.lastPass(TrashSettingsView.lastPass(for: zone)),
                ]
                : []
            return usage + zone.events.map(TrashEventLabel.text(for:))
        }

        private var moreInfoButton: some View {
            Button {
                withAnimation(DSMotion.contentReveal) { isExpanded.toggle() }
            } label: {
                HStack(spacing: .space4) {
                    Text(L10n.Common.moreInfo)
                    (isExpanded ? IconKit.chevronUp : IconKit.chevronDown)
                        .imageScale(.small)
                }
                .type(.body3(.semibold))
                .foregroundStyle(Color.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, .space4)
            .accessibilityValue(isExpanded ? L10n.Common.on : L10n.Common.off)
        }

        private var details: some View {
            VStack(alignment: .leading, spacing: .space8) {
                Rectangle()
                    .fill(Color.macLine)
                    .frame(height: .borderWidthHairline)
                ForEach(info, id: \.self) { line in
                    Text(line)
                        .type(.body3(.regular), style: .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, .space16)
            .padding(.bottom, .space12)
            .transition(.opacity)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: .zero) {
                MacFormRow {
                    VStack(alignment: .leading, spacing: .space2) {
                        Text(TrashSettingsView.label(for: zone))
                        if zone.isAvailable {
                            Text(counts).type(.body3(.regular), style: .secondary)
                        }
                        if !info.isEmpty {
                            moreInfoButton
                        }
                    }
                    .padding(.vertical, .space4)
                } control: {
                    HStack(spacing: .space8) {
                        if problems > 0 {
                            MacChip(text: L10n.TrashSettings.zoneProblems(problems), tone: .red)
                        }
                        MacChip(text: TrashSettingsView.state(for: zone), tone: zone.isAvailable ? .green : .red)
                    }
                }
                if isExpanded {
                    details
                }
            }
        }
    }

    #Preview("Zones") {
        MacFormGroup(L10n.TrashSettings.zonesHeader) {
            MacTrashZoneRow(zone: PreviewZones.available, problems: 0)
            MacTrashZoneRow(zone: PreviewZones.available, problems: 2)
            MacTrashZoneRow(zone: PreviewZones.missing, problems: 0)
        }
        .padding()
        .previewCanvasWidth(.dialog)
        .background(Color.macCard)
    }
#endif
