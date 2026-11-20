#if os(iOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    private enum Constants {
        static let expiryAnchor = "expiry"
        static let savingOpacity: Double = 0.5
    }

    /// Edit for one share, pushed inside the detail sheet on top of its share page. Save is the
    /// check in the bar; once something changed Back asks before throwing the edits away. An expired share lands
    /// scrolled to Expires with the calendar open.
    struct EditSharePage: View {
        @Bindable var store: StoreOf<EditShareFeature>
        @State private var isCalendarShown: Bool
        @State private var isShowingPeople = false

        init(store: StoreOf<EditShareFeature>) {
            self.store = store
            _isCalendarShown = State(initialValue: store.isExpired)
        }

        private var discardBinding: Binding<Bool> {
            // No op setter: the alert only closes through its own buttons, which drive the reducer.
            Binding(get: { store.isConfirmingDiscard }, set: { _ in })
        }

        var body: some View {
            ScrollViewReader { proxy in
                DSGroupedList {
                    if let errorMessage = store.errorMessage ?? store.usersPhase.errorMessage {
                        Section { DSErrorCard(errorMessage).clearRow() }
                    }
                    labelSection
                    audienceSection
                    accessSection
                    passwordSection
                    EditShareExpirySection(store: store, isCalendarShown: $isCalendarShown)
                        .id(Constants.expiryAnchor)
                }
                .sharedSheetList()
                .disabled(store.isSaving)
                .opacity(store.isSaving ? Constants.savingOpacity : 1)
                .onAppear {
                    if store.isExpired {
                        proxy.scrollTo(Constants.expiryAnchor, anchor: .top)
                    }
                }
            }
            .navigationTitle(L10n.EditShare.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(store.isLeavingGuarded)
            .toolbar { toolbar }
            .navigationDestination(isPresented: $isShowingPeople) {
                EditSharePeoplePage(store: store)
            }
            .task { store.send(.task) }
            .dsAlert(isPresented: discardBinding) {
                DSAlertSheet(
                    icon: IconKit.delete,
                    title: L10n.EditShare.discardTitle,
                    message: L10n.EditShare.discardMessage,
                    confirmTitle: L10n.EditShare.discard,
                    dismissTitle: L10n.EditShare.keepEditing,
                    role: .destructive,
                    closeAccessibilityLabel: L10n.Common.close,
                    onConfirm: { store.send(.discardConfirmed) },
                    onDismiss: { store.send(.discardCancelled) }
                )
            }
        }

        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            if store.isLeavingGuarded {
                // Stands in for the system Back, which cannot ask first, so leaving with edits confirms.
                ToolbarItem(placement: .topBarLeading) {
                    Button { store.send(.cancelTapped) } label: {
                        IconKit.back.foregroundStyle(Color.primaryDS)
                    }
                    .disabled(store.isSaving)
                    .accessibilityLabel(L10n.Common.back)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button { store.send(.saveTapped) } label: {
                    if store.isSaving {
                        DSSpinner()
                    } else {
                        IconKit.checkmark.foregroundStyle(Color.primaryInverted)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .disabled(!store.isSaveEnabled)
                .accessibilityLabel(L10n.EditShare.save)
                .accessibilityIdentifier(AccessibilityIdentifiers.Shared.saveEdit)
            }
        }

        private var labelSection: some View {
            Section {
                TextField(
                    L10n.CreateShare.sectionLabel,
                    text: $store.label.sending(\.labelChanged),
                    prompt: Text(verbatim: store.share.displayName)
                )
                .type(.body2(.regular), style: .primaryOnSurface)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .accessibilityIdentifier(AccessibilityIdentifiers.Shared.editLabel)
            } header: {
                DSFieldLabel(L10n.CreateShare.sectionLabel)
            }
        }

        private var audienceSection: some View {
            Section {
                EditShareChoices(
                    options: ShareTarget.allCases,
                    selection: store.target,
                    title: \.title,
                    hint: \.hint,
                    icon: \.icon,
                    onSelect: { store.send(.targetChanged($0), animation: DSMotion.stateFade) }
                )
                if store.target == .users {
                    peopleRow
                }
            } header: {
                DSFieldLabel(L10n.CreateShare.sectionWhoCanAccess)
            }
        }

        private var peopleRow: some View {
            Button { isShowingPeople = true } label: {
                HStack(spacing: .space8) {
                    Text(L10n.Shared.people).type(.body2(.regular), style: .primaryOnSurface)
                    Spacer(minLength: .space8)
                    peopleSummary
                    IconKit.chevronRight
                        .foregroundStyle(Color.tertiaryDS)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(DSPressableButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityIdentifiers.Shared.editPeople)
        }

        @ViewBuilder
        private var peopleSummary: some View {
            if store.usersPhase == .loading {
                DSSpinner()
            } else if store.selectedUserIDs.isEmpty {
                Text(L10n.Common.none).type(.body2(.regular), style: .secondary)
            } else {
                let people = store.selectedUsers.map {
                    SharedFeature.Person(id: $0.id, name: $0.displayName ?? $0.username)
                }
                SharedPeopleStack(
                    badge: SharedFeature.ShareBadge(
                        id: store.share.id,
                        isAnyone: false,
                        people: people,
                        unnamedCount: store.selectedUserIDs.count - people.count,
                        expiry: nil
                    )
                )
            }
        }

        private var accessSection: some View {
            Section {
                EditShareChoices(
                    options: ShareAccessMode.allCases,
                    selection: store.accessMode,
                    title: \.title,
                    hint: { [isDirectory = store.share.isDirectory] in $0.hint(isDirectory: isDirectory) },
                    icon: \.icon,
                    onSelect: { store.send(.accessModeChanged($0)) }
                )
            } header: {
                DSFieldLabel(L10n.Shared.metaAccess)
            }
        }

        private var passwordSection: some View {
            Section {
                DSToggleRow(
                    title: L10n.CreateShare.togglePasswordProtect,
                    icon: IconKit.lock,
                    isOn: $store.wantsPassword.sending(\.wantsPasswordChanged).animation(DSMotion.stateFade)
                )
                if store.wantsPassword {
                    SecureField(
                        L10n.Common.password,
                        text: $store.newPassword.sending(\.newPasswordChanged),
                        prompt: Text(store.share.hasPassword ? L10n.EditShare.passwordKeepHint : L10n.Common.password)
                    )
                    .type(.body2(.regular), style: .primaryOnSurface)
                    .textContentType(.newPassword)
                }
            } header: {
                DSFieldLabel(L10n.Common.password)
            } footer: {
                if let error = store.fieldError, error == .passwordRequired {
                    Text(error.message).type(.body3(.regular), style: .error)
                }
            }
        }
    }

    /// An edit store for a share over the mock services, for the edit pages' previews.
    @MainActor
    func editSharePreviewStore(
        _ share: Share,
        mutate: (inout EditShareFeature.State) -> Void = { _ in }
    ) -> StoreOf<EditShareFeature> {
        var state = EditShareFeature.State(serverURL: sharedPreviewServerURL, share: share, now: .now)
        mutate(&state)
        return Store(initialState: state) { EditShareFeature() } withDependencies: {
            $0.filesClient = .previewValue
        }
    }

    /// The edit page over the mock services, opened inside a navigation stack like the sheet does.
    @MainActor
    private func editSharePreview(
        _ share: Share,
        mutate: (inout EditShareFeature.State) -> Void = { _ in }
    ) -> some View {
        NavigationStack { EditSharePage(store: editSharePreviewStore(share, mutate: mutate)) }
    }

    #Preview("Specific users, clean") {
        editSharePreview(.previewCard(target: .users)) {
            $0.selectedUserIDs = ["u4", "u5", "u6", "u2"]
        }
    }

    #Preview("Changed, dark") {
        editSharePreview(.previewCard(expiresAt: Date().addingTimeInterval(86_400 * 30))) {
            $0.label = "Board preview"
        }
        .preferredColorScheme(.dark)
    }

    #Preview("Expired lands on Expires") {
        editSharePreview(.previewCard(expiresAt: Date().addingTimeInterval(-86_400 * 9)))
    }

    #Preview("Password required") {
        editSharePreview(.previewCard()) {
            $0.wantsPassword = true
            $0.fieldError = .passwordRequired
        }
    }

    #Preview("Saving") {
        editSharePreview(.previewCard()) {
            $0.label = "Renamed"
            $0.isSaving = true
        }
    }

    #Preview("Save error") {
        editSharePreview(.previewCard()) {
            $0.label = "Renamed"
            $0.errorMessage = FilesClientError.offline.userMessage
        }
    }

    #Preview("iPad tiles") {
        editSharePreview(.previewCard(target: .users))
            .environment(\.horizontalSizeClass, .regular)
    }

    #Preview("Large type") {
        editSharePreview(.previewCard())
            .dynamicTypeSize(.accessibility2)
    }
#endif
