#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let tileDate = Date.FormatStyle.dateTime.month(.abbreviated).day()
    }

    struct MacShareDetail: View {
        let store: StoreOf<SharedFeature>
        let isByMe: Bool
        let share: Share
        let badge: SharedFeature.ShareBadge?
        let onToast: (DSToastMessage) -> Void

        @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue

        private var isDeleting: Bool {
            store.deletingIDs.contains(share.id)
        }

        private var canEdit: Bool {
            isByMe && store.state.expiryNotice(for: share) != .expired
        }

        private var pendingEdit: EditShareFeature.State? {
            store.editPopover == .inline && store.editSheet?.share.id == share.id ? store.editSheet : nil
        }

        private var shownChoice: ShareAccessChoice {
            if let pendingEdit {
                return pendingEdit.accessChoice
            }
            return store.customShareID == share.id ? .custom : share.accessChoice
        }

        private var shownPermissions: SharePermissions {
            pendingEdit?.permissions ?? share.permissions.effective(for: share.accessMode)
        }

        private var unnamedCount: Int {
            badge?.unnamedCount ?? 0
        }

        var body: some View {
            let facts = SharedShareFacts(
                share: share,
                notice: store.state.expiryNotice(for: share),
                dateFormat: DateDisplayFormat(rawValue: dateFormatRaw) ?? .system
            )
            VStack(alignment: .leading, spacing: MacInspectorMetrics.sectionSpacing) {
                link(facts)
                tiles(facts)
                people
                access(facts)
                if !isByMe {
                    Text(L10n.Shared.controlsShare(store.state.sharedByLabel(for: share)))
                        .type(.body3(.regular), style: .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(isDeleting ? SharedRowMetrics.deletingOpacity : 1)
            .disabled(isDeleting)
        }

        @ViewBuilder
        private func link(_ facts: SharedShareFacts) -> some View {
            if isByMe, facts.isExpired {
                VStack(alignment: .leading, spacing: .space8) {
                    if let note = facts.expiredNote {
                        Text(note)
                            .type(.body3(.regular), style: .error)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button(L10n.Shared.setNewDate) { store.send(.editPopoverTapped(share, .renew)) }
                        .buttonStyle(.macDS(.primary, size: .small))
                        .popover(isPresented: isPresenting(.renew), arrowEdge: .top) { expiryPopover }
                }
            } else {
                MacShareLinkField(
                    share: share,
                    serverURL: store.serverURL,
                    showsDirectLink: isByMe
                ) { onToast(.success($0)) }
            }
        }

        private func tiles(_ facts: SharedShareFacts) -> some View {
            HStack(alignment: .top, spacing: .space8) {
                if isByMe {
                    MacShareStatTile(value: facts.downloads, label: L10n.Shared.metaDownloads)
                    MacShareStatTile(value: facts.lastOpenedShort, label: L10n.Shared.metaLastOpened)
                }
                MacShareStatTile(
                    value: share.createdAt.formatted(Metrics.tileDate),
                    label: isByMe ? L10n.Shared.metaShared : L10n.Shared.metaReceived
                )
            }
        }

        private var people: some View {
            VStack(alignment: .leading, spacing: .space12) {
                MacInspectorSectionHeader(
                    title: isByMe ? L10n.Shared.metaSharedWith : L10n.Shared.metaSharedBy,
                    count: isByMe && badge?.isAnyone == false ? (badge?.people.count ?? 0) + unnamedCount : nil,
                    actionTitle: canEdit && badge?.isAnyone == false ? L10n.Common.change : nil,
                    action: canEdit && badge?.isAnyone == false
                        ? { store.send(.editPopoverTapped(share, .limit)) }
                        : nil
                )
                .popover(
                    isPresented: isPresenting(.limit, when: badge?.isAnyone == false),
                    attachmentAnchor: .point(.trailing),
                    arrowEdge: .top
                ) { audiencePopover }
                MacInspectorGroup {
                    if badge?.isAnyone == true {
                        MacShareAnyoneRow(onLimit: canEdit ? { store.send(.editPopoverTapped(share, .limit)) } : nil)
                            .popover(
                                isPresented: isPresenting(.limit),
                                attachmentAnchor: .point(.trailing),
                                arrowEdge: .top
                            ) { audiencePopover }
                    } else {
                        ForEach(badge?.people ?? []) { person in
                            MacSharePersonRow(name: person.name, email: store.userEmails[person.id])
                        }
                        if unnamedCount > 0 {
                            MacInspectorRow(L10n.Shared.people, L10n.Shared.peopleCount(unnamedCount))
                        }
                    }
                }
            }
        }

        private func access(_ facts: SharedShareFacts) -> some View {
            VStack(alignment: .leading, spacing: .space12) {
                MacInspectorSectionHeader(title: L10n.Shared.metaAccess)
                MacInspectorGroup {
                    if canEdit {
                        MacInspectorControlRow(label: L10n.MacSettings.permission) {
                            MacPopup(
                                L10n.MacSettings.permission,
                                valueLabel: shownChoice.title,
                                selection: Binding(
                                    get: { shownChoice },
                                    set: { store.send(.accessChoiceChosen(share, $0)) }
                                )
                            ) {
                                ForEach(
                                    ShareAccessChoice.options(isDirectory: share.isDirectory, current: shownChoice),
                                    id: \.self
                                ) { Text($0.title).tag($0) }
                            }
                            .fixedSize()
                        }
                        if shownChoice == .custom {
                            ForEach(SharePermissionSwitch.options(isDirectory: share.isDirectory), id: \.self) { item in
                                MacInspectorPermissionRow(item: item, isOn: shownPermissions[keyPath: item.keyPath]) {
                                    var permissions = shownPermissions
                                    permissions[keyPath: item.keyPath] = $0
                                    store.send(.permissionsChosen(share, permissions))
                                }
                            }
                        }
                        editableRow(L10n.Common.password, value: facts.password, popover: .password) {
                            passwordPopover
                        }
                        editableRow(
                            facts.expiresTitle,
                            value: facts.expires,
                            color: expiresColor(facts),
                            popover: .expiry
                        ) {
                            expiryPopover
                        }
                    } else {
                        MacInspectorRow(L10n.MacSettings.permission, share.accessChoice.title)
                        if share.accessChoice == .custom {
                            ForEach(SharePermissionSwitch.options(isDirectory: share.isDirectory), id: \.self) { item in
                                MacInspectorPermissionRow(item: item, isOn: share.permissions[keyPath: item.keyPath])
                            }
                        }
                        MacInspectorRow(L10n.Common.password, facts.password)
                        MacInspectorRow(facts.expiresTitle, facts.expires, valueColor: expiresColor(facts))
                    }
                }
            }
        }

        private func editableRow(
            _ label: String,
            value: String,
            color: Color = Color.accentText,
            popover: SharedFeature.EditPopover,
            @ViewBuilder content: @escaping () -> some View
        ) -> some View {
            Button { store.send(.editPopoverTapped(share, popover)) } label: {
                MacInspectorRow(label, value, valueColor: color)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(
                isPresented: isPresenting(popover),
                attachmentAnchor: .point(.trailing),
                arrowEdge: .top,
                content: content
            )
        }

        private func expiresColor(_ facts: SharedShareFacts) -> Color {
            if facts.notice != nil {
                return facts.expiresStyle.color
            }
            if isByMe {
                return Color.accentText
            }
            return Color.primaryDS
        }

        private func isPresenting(_ popover: SharedFeature.EditPopover, when isShown: Bool = true) -> Binding<Bool> {
            Binding(
                get: { isShown && store.editPopover == popover && store.editSheet?.share.id == share.id },
                set: { isPresented in
                    if !isPresented, store.editPopover == popover {
                        store.send(.editPopoverDismissed)
                    }
                }
            )
        }

        private var audiencePopover: some View {
            MacEditPopoverHost(store: store) { editStore in
                MacShareAudiencePopover(store: editStore) { store.send(.editPopoverDismissed) }
            }
        }

        private var passwordPopover: some View {
            MacEditPopoverHost(store: store) { editStore in
                MacSharePasswordPopover(store: editStore) { store.send(.editPopoverDismissed) }
            }
        }

        private var expiryPopover: some View {
            MacEditPopoverHost(store: store) { editStore in
                MacExpiryPopover(store: editStore) { store.send(.editPopoverDismissed) }
            }
        }
    }

    struct MacEditPopoverHost<Content: View>: View {
        let store: StoreOf<SharedFeature>
        @ViewBuilder let content: (StoreOf<EditShareFeature>) -> Content
        @State private var heldStore: StoreOf<EditShareFeature>?

        var body: some View {
            if let editStore = heldStore ?? store.scope(state: \.editSheet, action: \.editSheet.presented) {
                content(editStore)
                    .onAppear { heldStore = editStore }
            }
        }
    }

    #Preview("Share detail, by me") {
        MacShareDetail(
            store: Store(initialState: sharedPreviewState()) { SharedFeature() },
            isByMe: true,
            share: Share.previewSharedByMe[0],
            badge: nil,
            onToast: { _ in }
        )
        .padding(MacInspectorMetrics.padding)
        .frame(width: MacInspectorMetrics.width)
        .background(Color.macCard)
    }
#endif
