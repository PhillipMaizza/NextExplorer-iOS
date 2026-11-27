#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let audienceIconWidth: CGFloat = .size24
        static let tileSize: CGFloat = 52
        static let expiredOpacity: Double = .opacityHalf
        static let shareButtonSize: CGFloat = .size36
    }

    struct MacSharedInspector: View {
        let store: StoreOf<SharedFeature>
        let segment: SharedFeature.Segment
        let item: SharedFeature.Item
        var selectedShareID: Share.ID?
        var onSelectShare: (Share.ID) -> Void = { _ in }
        var onOpen: (Share) -> Void = { _ in }
        let onToast: (DSToastMessage) -> Void

        private var previewItem: FileItem? {
            share.flatMap { store.shareFiles[$0.id] }
        }

        private var isExpiredShare: Bool {
            share.map { store.state.expiryNotice(for: $0) == .expired } ?? false
        }

        private var isByMe: Bool {
            segment == .byMe
        }

        private var share: Share? {
            if let selectedShareID, let selected = item.shares.first(where: { $0.id == selectedShareID }) {
                return selected
            }
            return item.shares.count == 1 ? item.shares.first : nil
        }

        private var subtitle: String {
            let label = share?.trimmedLabel.flatMap { $0 == item.title ? nil : L10n.Shared.quotedLabel($0) }
            let place = isByMe
                ? MacInspectorLocation.trail(parent: item.location ?? "")
                : L10n.Shared.fromSharer(store.state.sharedByLabel(for: share ?? item.shares[0]))
            return ServerSettingsMetrics.joined([label, place].compactMap { $0 })
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: MacInspectorMetrics.sectionSpacing) {
                    header
                    if !isByMe, let share, !isExpiredShare {
                        Button { onOpen(share) } label: {
                            Label { Text(L10n.Browse.open) } icon: {
                                share.isDirectory ? IconKit.folder : IconKit.document
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.macDS(.primary))
                        .accessibilityIdentifier(AccessibilityIdentifiers.Shared.openShare)
                    }
                    if let share {
                        MacShareDetail(
                            store: store,
                            isByMe: isByMe,
                            share: share,
                            badge: item.badges.first { $0.id == share.id },
                            onToast: onToast
                        )
                    } else {
                        shareList
                    }
                }
                .padding(MacInspectorMetrics.padding)
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { store.send(.labelEditEnded) }
                }
            }
            .scrollIndicators(.never)
            .defaultScrollAnchor(.top)
            .safeAreaInset(edge: .bottom, spacing: .zero) {
                if isByMe, let share {
                    Button(L10n.Shared.deleteLink) { store.send(.deleteTapped(share)) }
                        .buttonStyle(.plain)
                        .type(.body3(.semibold))
                        .foregroundStyle(Color.negativeText)
                        .disabled(store.deletingIDs.contains(share.id))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(MacInspectorMetrics.padding)
                        .background(Color.macCard)
                        .accessibilityIdentifier(AccessibilityIdentifiers.Shared.deleteShare)
                }
            }
            .id(share?.id ?? item.id)
        }

        private var header: some View {
            Group {
                if let previewItem, let kind = MacInspectorPreview.Kind(previewItem) {
                    VStack(alignment: .leading, spacing: .space16) {
                        MacInspectorPreview(item: previewItem, kind: kind, serverURL: store.serverURL)
                            .frame(maxWidth: .infinity)
                            .frame(height: MacInspectorMetrics.pictureHeight)
                            .background(Color.macRow)
                            .clipShape(RoundedRectangle(cornerRadius: .radiusMedium, style: .continuous))
                        HStack(alignment: .top, spacing: .space16) {
                            titles
                            shareButton
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: .space16) {
                        MacItemTile(name: item.name, isDirectory: item.shares[0].isDirectory, size: Metrics.tileSize)
                            .opacity(item.isExpired ? Metrics.expiredOpacity : 1)
                        titles
                        shareButton
                    }
                }
            }
            .task(id: share?.id) {
                if isByMe, let share {
                    store.send(.shareFileNeeded(share))
                }
            }
        }

        private var titles: some View {
            VStack(alignment: .leading, spacing: .space4) {
                MacShareTitle(store: store, name: item.title, share: share, isEditable: isByMe && !isExpiredShare)
                Text(subtitle)
                    .type(.body3(.regular), style: .secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        @ViewBuilder
        private var shareButton: some View {
            if isByMe, let share, let url = URL(string: share.shareLink(serverURL: store.serverURL)) {
                ShareLink(item: url) {
                    IconKit.share
                        .foregroundStyle(Color.primaryDS)
                        .frame(width: Metrics.shareButtonSize, height: Metrics.shareButtonSize)
                        .background(Circle().fill(Color.macRow))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabelWithTooltip(L10n.Common.share)
            }
        }

        private var shareList: some View {
            VStack(alignment: .leading, spacing: .space12) {
                MacInspectorSectionHeader(title: L10n.Shared.links, count: item.shares.count)
                MacInspectorGroup {
                    ForEach(item.shares) { share in
                        Button { onSelectShare(share.id) } label: {
                            HStack(spacing: .space12) {
                                share.audienceIcon
                                    .foregroundStyle(Color.macChromeSecondary)
                                    .frame(width: Metrics.audienceIconWidth)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: .space2) {
                                    Text(share.audienceTitle)
                                        .type(.body3(.semibold))
                                        .lineLimit(1)
                                    if let label = share.trimmedLabel {
                                        Text(label)
                                            .type(.caption(.regular), style: .secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: .space8)
                                IconKit.chevronRight
                                    .foregroundStyle(Color.macChromeSecondary)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: MacInspectorMetrics.rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @MainActor
    private func inspectorPreview(
        _ itemID: SharedFeature.Item.ID,
        segment: SharedFeature.Segment = .byMe,
        shareID: Share.ID? = nil,
        mutate: (inout SharedFeature.State) -> Void = { _ in }
    ) -> some View {
        macSharedPreview(segment, mutate: mutate) { store in
            if let item = store.state.item(for: SharedFeature.Detail(segment: segment, id: itemID)) {
                MacSharedInspector(
                    store: store,
                    segment: segment,
                    item: item,
                    selectedShareID: shareID,
                    onToast: { _ in }
                )
                .frame(width: MacInspectorMetrics.width)
                .background(Color.macCard)
            }
        }
        .frame(height: PreviewCanvas.window.size.height)
    }

    #Preview("Inspector: two shares") {
        inspectorPreview("personal:Work/Team Roadmap")
    }

    #Preview("Inspector: one of two shares") {
        inspectorPreview("personal:Work/Team Roadmap", shareID: "s5")
    }

    #Preview("Inspector: expiring soon, dark") {
        inspectorPreview("personal:Photos/2026/Vacation Photos")
            .preferredColorScheme(.dark)
    }

    #Preview("Inspector: expired") {
        inspectorPreview("personal:Design/Brand/Logo final.png")
    }

    #Preview("Inspector: deleting") {
        inspectorPreview("personal:Finance/Budget 2027.xlsx") { $0.deletingIDs = ["s8"] }
    }

    #Preview("Inspector: with me") {
        inspectorPreview("w2", segment: .withMe)
    }

    #Preview("Inspector: with me, dark") {
        inspectorPreview("w2", segment: .withMe)
            .preferredColorScheme(.dark)
    }

    #Preview("Inspector: large type") {
        inspectorPreview("personal:Work/Meeting notes.md")
            .dynamicTypeSize(.xxxLarge)
    }
#endif
