#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 350
        static let offOpacity: Double = .opacityHalf
        static let endsDate = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()
    }

    private enum ExpiryShortcut: Int, CaseIterable {
        case tomorrow = 1
        case week = 7
        case month = 30

        var title: String {
            switch self {
            case .tomorrow: L10n.Shared.tomorrow
            case .week: L10n.Shared.inSevenDays
            case .month: L10n.Shared.inThirtyDays
            }
        }
    }

    struct MacShareEditPopover<Content: View>: View {
        let store: StoreOf<EditShareFeature>
        var isSaveEnabled: Bool?
        let onSave: () -> Void
        let onCancel: () -> Void
        @ViewBuilder let content: () -> Content

        private var errorMessage: String? {
            store.fieldError?.message ?? store.errorMessage ?? store.usersPhase.errorMessage
        }

        var body: some View {
            VStack(alignment: .leading, spacing: .space16) {
                content()
                if let errorMessage {
                    MacNote(errorMessage, kind: .error)
                }
                HStack(spacing: .space8) {
                    Spacer()
                    Button(L10n.Common.cancel, action: onCancel)
                        .buttonStyle(.macDS(.secondary, size: .small))
                        .keyboardShortcut(.cancelAction)
                    Button(L10n.Common.save, action: onSave)
                        .buttonStyle(.macDS(.primary, size: .small))
                        .keyboardShortcut(.defaultAction)
                        .disabled(!(isSaveEnabled ?? store.isSaveEnabled))
                }
            }
            .padding(.space16)
            .frame(width: Metrics.width)
            .presentationBackground(Color.macCard)
            .disabled(store.isSaving)
            .task { store.send(.task) }
        }
    }

    struct MacExpiryPopover: View {
        @Bindable var store: StoreOf<EditShareFeature>
        let onCancel: () -> Void

        @Environment(\.calendar) private var calendar

        private var earliestDay: Date {
            calendar.date(byAdding: .day, value: 1, to: store.openedAt) ?? store.openedAt
        }

        private var footer: String {
            guard store.isExpiryEnabled else { return L10n.EditShare.neverFooter }
            return ServerSettingsMetrics.joined([
                L10n.Shared.endsOn(store.expiresAt.formatted(Metrics.endsDate)),
                L10n.Shared.daysLeft(store.daysLeft),
            ])
        }

        var body: some View {
            MacShareEditPopover(store: store, onSave: { store.send(.saveTapped) }, onCancel: onCancel) {
                Toggle(isOn: $store.isExpiryEnabled.sending(\.expiryEnabledChanged)) {
                    Text(L10n.Shared.linkExpires)
                        .type(.body2(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.macSwitch)
                HStack(spacing: .space8) {
                    ForEach(ExpiryShortcut.allCases, id: \.self) { shortcut in
                        Button(shortcut.title) { store.send(.expiryDaysTapped(shortcut.rawValue)) }
                            .buttonStyle(.macDS(.secondary, size: .small))
                    }
                }
                MacMonthCalendar(selection: $store.expiresAt.sending(\.expiresAtChanged), minimum: earliestDay)
                    .opacity(store.isExpiryEnabled ? 1 : Metrics.offOpacity)
                Text(footer)
                    .type(.body3(.regular), style: .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    struct MacShareAudiencePopover: View {
        @Bindable var store: StoreOf<EditShareFeature>
        let onCancel: () -> Void

        var body: some View {
            MacShareEditPopover(store: store, onSave: { store.send(.saveTapped) }, onCancel: onCancel) {
                Text(L10n.CreateShare.sectionWhoCanAccess)
                    .type(.body2(.bold))
                    .accessibilityAddTraits(.isHeader)
                MacSegmentedPicker(
                    L10n.CreateShare.sectionWhoCanAccess,
                    options: ShareTarget.allCases,
                    selection: $store.target.sending(\.targetChanged)
                ) { $0.title }
                if store.target == .users {
                    MacShareUserPicker(
                        users: Array(store.shareableUsers),
                        selectedUserIDs: store.selectedUserIDs,
                        usersPhase: store.usersPhase,
                        onToggleUser: { store.send(.userToggled($0)) }
                    )
                } else {
                    Text(store.target.hint)
                        .type(.caption(.regular), style: .secondary)
                }
            }
        }
    }

    struct MacSharePasswordPopover: View {
        @Bindable var store: StoreOf<EditShareFeature>
        let onCancel: () -> Void

        var body: some View {
            MacShareEditPopover(
                store: store,
                isSaveEnabled: store.isSaveEnabled && !store.isPasswordMissing,
                onSave: { store.send(.saveTapped) },
                onCancel: onCancel
            ) {
                Toggle(isOn: $store.isPasswordEnabled.sending(\.wantsPasswordChanged)) {
                    Text(L10n.CreateShare.togglePasswordProtect)
                        .type(.body2(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.macSwitch)
                if store.isPasswordEnabled {
                    MacSecureField(
                        L10n.Common.password,
                        text: $store.newPassword.sending(\.newPasswordChanged),
                        prompt: Text(store.share.hasPassword ? L10n.EditShare.passwordKeepHint : L10n.Common.password)
                    )
                }
            }
        }
    }

    @MainActor
    private func editPreviewStore(_ share: Share) -> StoreOf<EditShareFeature> {
        Store(initialState: EditShareFeature.State(serverURL: sharedPreviewServerURL, share: share, now: .now)) {
            EditShareFeature()
        } withDependencies: { $0.filesClient = .previewValue }
    }

    #Preview("Link expires") {
        MacExpiryPopover(store: editPreviewStore(Share.previewSharedByMe[1]), onCancel: {})
    }

    #Preview("Who can access") {
        MacShareAudiencePopover(store: editPreviewStore(Share.previewSharedByMe[0]), onCancel: {})
    }

    #Preview("Password") {
        MacSharePasswordPopover(store: editPreviewStore(Share.previewSharedByMe[0]), onCancel: {})
    }
#endif
