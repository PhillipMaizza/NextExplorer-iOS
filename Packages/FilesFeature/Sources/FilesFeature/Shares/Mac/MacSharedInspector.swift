#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let iconSize: CGFloat = .size44
        static let folderGlyphSize: CGFloat = .size40
        static let audienceGlyphSize: CGFloat = .iconSmall
        static let deletingOpacity: Double = 0.4
        static let expiredOpacity: Double = 0.5
    }

    /// Get Info for a shared item: its icon and summary, then one grouped section per share. By me
    /// shows who it reaches, its links, facts, Edit and Delete; With me who shared it and its facts.
    struct MacSharedInspector: View {
        let store: StoreOf<SharedFeature>
        let segment: SharedFeature.Segment
        let item: SharedFeature.Item
        let onToast: (DSToastMessage) -> Void

        private var isByMe: Bool {
            segment == .byMe
        }

        private var subtitle: String {
            isByMe
                ? SharedDetailHero.summary(of: item)
                : L10n.Shared.fromSharer(store.state.sharedByLabel(for: item.shares[0]))
        }

        var body: some View {
            Form {
                Section {
                    HStack(alignment: .top, spacing: .space12) {
                        SharedItemIcon(
                            share: item.shares[0],
                            name: item.name,
                            serverURL: store.serverURL,
                            isByMe: isByMe,
                            folderGlyphSize: Metrics.folderGlyphSize
                        )
                        .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                        .opacity(item.isExpired ? Metrics.expiredOpacity : 1)
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: .space2) {
                            Text(item.name)
                                .font(.headline)
                                .lineLimit(3)
                                .textSelection(.enabled)
                            Text(subtitle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                ForEach(item.shares) { share in
                    MacSharedShareCard(
                        store: store,
                        isByMe: isByMe,
                        share: share,
                        badge: item.badges.first { $0.id == share.id },
                        onToast: onToast
                    )
                }
            }
            .formStyle(.grouped)
            // Neutral controls: the app accent stays on our own elements, only Delete reads red.
            .tint(Color.primaryDS)
            .frame(width: MacInspectorMetrics.width)
        }
    }

    /// One share in the inspector. By me: who it reaches with its label, the people, the copy
    /// buttons (or Set a New Date once expired), the facts, then Edit and Delete. With me: who shared
    /// it, the facts, and that only they can change it.
    private struct MacSharedShareCard: View {
        let store: StoreOf<SharedFeature>
        let isByMe: Bool
        let share: Share
        let badge: SharedFeature.ShareBadge?
        let onToast: (DSToastMessage) -> Void

        @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue
        @State private var directLinkMode: DirectLinkMode = .auto

        private var isDeleting: Bool {
            store.deletingIDs.contains(share.id)
        }

        var body: some View {
            let facts = SharedShareFacts(
                share: share,
                notice: store.state.expiryNotice(for: share),
                dateFormat: DateDisplayFormat(rawValue: dateFormatRaw) ?? .system
            )
            Section {
                if isByMe {
                    audience
                    if let badge, !badge.isAnyone {
                        SharedPeopleCircles(badge: badge)
                    }
                    links(isExpired: facts.isExpired)
                    Picker(facts.linkModeTitle, selection: $directLinkMode) {
                        ForEach(DirectLinkMode.allCases) { Text($0.title).tag($0) }
                    }
                } else if let badge {
                    SharedPeopleCircles(badge: badge)
                }
                MacInfoRow(L10n.Shared.metaAccess, share.accessMode.title)
                MacInfoRow(L10n.Common.password, facts.password)
                MacInfoRow(
                    facts.expiresTitle,
                    facts.expires,
                    valueColor: facts.notice == nil ? nil : facts.expiresStyle.color
                )
                if !isByMe {
                    MacInfoRow(L10n.Shared.metaLabel, facts.label)
                }
                MacInfoRow(isByMe ? L10n.Shared.metaShared : L10n.Shared.metaReceived, facts.created)
                if isByMe {
                    MacInfoRow(L10n.Shared.metaLastOpened, facts.lastOpened)
                    MacInfoRow(L10n.Shared.metaDownloads, facts.downloads)
                    HStack {
                        Spacer()
                        Button(L10n.ellipsized(L10n.Common.edit)) { store.send(.editTapped(share)) }
                        Button(L10n.Common.delete, role: .destructive) { store.send(.deleteTapped(share)) }
                            .tint(Color.negativeText)
                            .accessibilityIdentifier(AccessibilityIdentifiers.Shared.deleteShare)
                    }
                }
            } header: {
                if !isByMe {
                    Text(L10n.Shared.metaSharedBy)
                }
            } footer: {
                if isByMe, let note = facts.expiredNote {
                    Text(note).font(.callout).foregroundStyle(Color.negativeText)
                } else if !isByMe {
                    Text(L10n.Shared.controlsShare(store.state.sharedByLabel(for: share)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(isDeleting ? Metrics.deletingOpacity : 1)
            .disabled(isDeleting)
        }

        private var audience: some View {
            HStack(spacing: .space8) {
                share.audienceIcon
                    .resizable().scaledToFit()
                    .foregroundStyle(.secondary)
                    .frame(width: Metrics.audienceGlyphSize, height: Metrics.audienceGlyphSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: .space2) {
                    Text(share.audienceTitle).fontWeight(.semibold)
                    if let label = share.trimmedLabel {
                        Text(label).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }

        @ViewBuilder
        private func links(isExpired: Bool) -> some View {
            if isExpired {
                Button(L10n.Shared.setNewDate) { store.send(.editTapped(share)) }
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: .space8) {
                    Button {
                        onToast(.success(share.copyShareLink(serverURL: store.serverURL)))
                    } label: {
                        Text(L10n.Shared.copyShareLink).frame(maxWidth: .infinity)
                    }
                    Button {
                        onToast(.success(share.copyDirectLink(serverURL: store.serverURL, mode: directLinkMode)))
                    } label: {
                        Text(share.isDirectory ? L10n.Shared.copyFolderLink : L10n.Shared.copyFileLink)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @MainActor
    private func inspectorPreview(
        _ itemID: SharedFeature.Item.ID,
        segment: SharedFeature.Segment = .byMe,
        mutate: (inout SharedFeature.State) -> Void = { _ in }
    ) -> some View {
        macSharedPreview(segment, mutate: mutate) { store in
            if let item = store.state.item(for: SharedFeature.Detail(segment: segment, id: itemID)) {
                MacSharedInspector(store: store, segment: segment, item: item, onToast: { _ in })
            }
        }
        .frame(height: PreviewCanvas.window.size.height)
    }

    #Preview("Inspector: two shares") {
        inspectorPreview("personal:Work/Team Roadmap")
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
