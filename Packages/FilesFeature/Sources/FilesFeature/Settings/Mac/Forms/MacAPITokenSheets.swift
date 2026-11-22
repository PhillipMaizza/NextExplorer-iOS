#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let secretHeight: CGFloat = 42
    }

    struct MacAPITokenCreateSheet: View {
        let store: StoreOf<APITokensFeature>

        var body: some View {
            let form = store.createForm
            MacFormSheet(
                title: L10n.ApiTokens.formTitle,
                confirmTitle: L10n.ApiTokens.createSubmit,
                isConfirmEnabled: store.isCreateEnabled,
                isWorking: store.isWorking,
                errorMessage: store.errorMessage,
                onCancel: { store.send(.createCancelled) },
                onConfirm: { store.send(.createSubmitted) }
            ) {
                if !store.isPasswordRequired {
                    MacNote(L10n.ApiTokens.noPasswordWarning, kind: .warning)
                }
                MacSettingsRow(L10n.ApiTokens.fieldName) {
                    MacTextField(
                        L10n.ApiTokens.fieldName,
                        text: Binding(get: { form?.name ?? "" }, set: { store.send(.nameChanged($0)) }),
                        prompt: L10n.ApiTokens.namePlaceholder
                    )
                    .accessibilityIdentifier(AccessibilityIdentifiers.Settings.apiTokenNameField)
                }
                MacSettingsRow(L10n.ApiTokens.fieldAccess) {
                    MacSegmentedPicker(
                        L10n.ApiTokens.fieldAccess,
                        options: APIToken.Scope.allCases,
                        selection: Binding(get: { form?.scope ?? .read }, set: { store.send(.scopeChanged($0)) })
                    ) { $0.title }
                }
                MacSettingsRow(L10n.ApiTokens.fieldExpiry) {
                    let expiry = form?.expiry ?? .days90
                    MacPopup(
                        L10n.ApiTokens.fieldExpiry,
                        valueLabel: expiry.title,
                        selection: Binding(get: { expiry }, set: { store.send(.expiryChanged($0)) }),
                        shouldFillWidth: true
                    ) {
                        ForEach(APITokensFeature.Expiry.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                if store.isPasswordRequired {
                    MacSettingsRow(L10n.ApiTokens.fieldPassword) {
                        MacSecureField(
                            L10n.ApiTokens.fieldPassword,
                            text: Binding(get: { form?.password ?? "" }, set: { store.send(.passwordChanged($0)) })
                        )
                        MacSettingsNote(L10n.ApiTokens.passwordHint)
                    }
                }
            }
        }
    }

    struct MacAPITokenRenameSheet: View {
        let store: StoreOf<APITokensFeature>

        var body: some View {
            MacFormSheet(
                title: L10n.ApiTokens.renameTitle,
                confirmTitle: L10n.ApiTokens.renameSave,
                isConfirmEnabled: store.isRenameEnabled,
                isWorking: store.isWorking,
                errorMessage: store.errorMessage,
                onCancel: { store.send(.renameCancelled) },
                onConfirm: { store.send(.renameSubmitted) }
            ) {
                MacSettingsRow(L10n.ApiTokens.fieldName) {
                    MacTextField(
                        L10n.ApiTokens.fieldName,
                        text: Binding(get: { store.rename?.name ?? "" }, set: { store.send(.renameNameChanged($0)) })
                    )
                }
            }
        }
    }

    struct MacAPITokenIssuedSheet: View {
        let issued: IssuedAPIToken
        let onDone: () -> Void
        @State private var isCopied = false

        var body: some View {
            MacFormSheet(
                title: L10n.ApiTokens.issuedTitle,
                message: L10n.ApiTokens.issuedIntro,
                confirmTitle: L10n.ApiTokens.issuedDone,
                cancelTitle: nil,
                onCancel: {},
                onConfirm: onDone
            ) {
                HStack(spacing: .space8) {
                    Text(issued.secret)
                        .type(.body3(.regular))
                        .monospaced()
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(isCopied ? L10n.ApiTokens.copiedToken : L10n.ApiTokens.copyToken) {
                        PlatformPasteboard.copy(issued.secret)
                        isCopied = true
                    }
                    .buttonStyle(.macDS(.primary, size: .small))
                    .fixedSize()
                }
                .padding(.leading, .space12)
                .padding(.trailing, .space8)
                .frame(height: Metrics.secretHeight)
                .background(RoundedRectangle(cornerRadius: .radiusControl, style: .continuous).fill(Color.macRow))
            }
            .interactiveDismissDisabled()
        }
    }

    extension View {
        func macAPITokenSheets(_ store: StoreOf<APITokensFeature>) -> some View {
            sheet(isPresented: Binding(get: { store.createForm != nil }, set: {
                if !$0 {
                    store.send(.createCancelled)
                }
            })) {
                MacAPITokenCreateSheet(store: store)
            }
            .sheet(isPresented: Binding(get: { store.rename != nil }, set: {
                if !$0 {
                    store.send(.renameCancelled)
                }
            })) {
                MacAPITokenRenameSheet(store: store)
            }
            .sheet(item: Binding(get: { store.issued }, set: { _ in })) { issued in
                MacAPITokenIssuedSheet(issued: issued) { store.send(.issuedDismissed) }
            }
            .sheet(item: Binding(get: { store.tokenPendingRevoke }, set: { _ in })) { token in
                MacAlertSheet(
                    title: L10n.ApiTokens.revokeTitle,
                    message: L10n.ApiTokens.revokeMessage(token.name),
                    confirmTitle: L10n.ApiTokens.revokeConfirm,
                    onConfirm: { store.send(.revokeConfirmed) },
                    onCancel: { store.send(.revokeCancelled) }
                )
            }
        }
    }

    private enum PreviewFixtures {
        static let serverURL = URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")
        static let token = APIToken(
            id: "t2",
            name: "home automation",
            scope: .write,
            createdAt: "2026-11-10T07:00:00.000Z"
        )

        @MainActor
        static func store(
            isPasswordRequired: Bool = true,
            _ edit: (inout APITokensFeature.State) -> Void
        ) -> StoreOf<APITokensFeature> {
            var state = APITokensFeature.State(
                serverURL: serverURL,
                isPasswordRequired: isPasswordRequired,
                phase: .loaded,
                tokens: [token]
            )
            edit(&state)
            return Store(initialState: state) { EmptyReducer<APITokensFeature.State, APITokensFeature.Action>() }
        }
    }

    #Preview("New token") {
        MacAPITokenCreateSheet(store: PreviewFixtures.store { $0.createForm = .init(name: "home automation") })
    }

    #Preview("New token, no password") {
        MacAPITokenCreateSheet(store: PreviewFixtures.store(isPasswordRequired: false) {
            $0.createForm = .init(name: "home automation")
        })
    }

    #Preview("New token, wrong password") {
        MacAPITokenCreateSheet(store: PreviewFixtures.store {
            $0.createForm = .init(name: "home automation")
            $0.errorMessage = "That password is not right."
        })
    }

    #Preview("Rename") {
        MacAPITokenRenameSheet(store: PreviewFixtures.store { $0.rename = .init(
            id: PreviewFixtures.token.id,
            name: PreviewFixtures.token.name
        ) })
    }

    #Preview("Secret") {
        MacAPITokenIssuedSheet(issued: IssuedAPIToken(
            token: PreviewFixtures.token,
            secret: "nxt_0123456789abcdef.0123456789abcdef0123456789abcdef"
        )) {}
    }
#endif
