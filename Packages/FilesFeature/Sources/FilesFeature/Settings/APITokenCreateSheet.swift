import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private typealias Metrics = APITokensMetrics

/// The form for a new token: name, access as the app's segmented control, how long it lasts as a
/// radio list, and the account password when the account has one. An account without a password
/// gets a warning instead, since the server then issues tokens without asking for one.
struct APITokenCreateSheet: View {
    @Bindable var store: StoreOf<APITokensFeature>
    @FocusState private var isNameFocused: Bool

    private var scope: Binding<APIToken.Scope> {
        Binding(get: { store.createForm?.scope ?? .read }, set: { store.send(.scopeChanged($0)) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    if !store.requiresPassword {
                        noPasswordWarning
                    }
                    LabeledField(L10n.ApiTokens.fieldName, uppercased: false) {
                        DSTextField(
                            L10n.ApiTokens.fieldName,
                            text: Binding(get: { store.createForm?.name ?? "" }, set: { store.send(.nameChanged($0)) }),
                            prompt: Text(L10n.ApiTokens.namePlaceholder),
                            focused: $isNameFocused
                        )
                        .accessibilityIdentifier(AccessibilityIdentifiers.Settings.apiTokenNameField)
                    }
                    LabeledField(L10n.ApiTokens.fieldAccess, uppercased: false) {
                        DSSegmentedControl(options: APIToken.Scope.allCases, selection: scope) { $0.title }
                    }
                    LabeledField(L10n.ApiTokens.fieldExpiry, uppercased: false) {
                        ChoiceRowList(
                            items: APITokensFeature.Expiry.allCases,
                            title: \.title,
                            isSelected: { $0 == (store.createForm?.expiry ?? .days90) },
                            onSelect: { store.send(.expiryChanged($0)) }
                        )
                        .dsCard()
                    }
                    if store.requiresPassword {
                        LabeledField(L10n.ApiTokens.fieldPassword, uppercased: false) {
                            DSSecureField(L10n.ApiTokens.fieldPassword, text: Binding(get: { store.createForm?.password ?? "" }, set: { store.send(.passwordChanged($0)) }))
                                .credentialContentType(.password)
                        }
                        Text(L10n.ApiTokens.passwordHint).type(.body3(.regular), style: .secondary)
                    }
                    if let message = store.errorMessage {
                        DSErrorCard(message)
                    }
                    DSButton(L10n.ApiTokens.createSubmit, style: .primary, isLoading: store.isWorking) {
                        store.send(.createSubmitted)
                    }
                    .disabled(!store.isCreateEnabled)
                    .formActionAlignment()
                }
                .padding(.horizontal, Metrics.horizontalPadding)
                .padding(.vertical, Metrics.sectionSpacing)
            }
            .backgroundGradient()
            .navigationTitle(L10n.ApiTokens.formTitle)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.Common.cancel) { store.send(.createCancelled) }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: Metrics.sheetMinWidth, minHeight: Metrics.sheetMinHeight)
        #endif
    }

    private var noPasswordWarning: some View {
        Card {
            HStack(alignment: .top, spacing: .space8) {
                IconKit.warning
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.attention)
                    .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
                    .padding(.top, .space2)
                    .accessibilityHidden(true)
                Text(L10n.ApiTokens.noPasswordWarning).type(.body3(.regular), style: .secondary)
            }
        }
    }
}

extension APITokensFeature.Expiry {
    var title: String {
        switch self {
        case .days30: L10n.ApiTokens.expiry30
        case .days90: L10n.ApiTokens.expiry90
        case .year: L10n.ApiTokens.expiryYear
        case .never: L10n.ApiTokens.expiryNever
        }
    }
}

private extension APIToken.Scope {
    var title: String {
        self == .write ? L10n.ApiTokens.scopeWrite : L10n.ApiTokens.scopeRead
    }
}

@MainActor
private func createSheetPreview(requiresPassword: Bool, configure: (inout APITokensFeature.State) -> Void = { _ in }) -> some View {
    var state = APITokensFeature.State(
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        requiresPassword: requiresPassword,
        phase: .loaded
    )
    state.createForm = .init(name: "ci runner", scope: .write)
    configure(&state)
    return APITokenCreateSheet(store: Store(initialState: state) { EmptyReducer() })
}

#Preview("With password") { createSheetPreview(requiresPassword: true) }
#Preview("No password: warning") { createSheetPreview(requiresPassword: false) }
#Preview("Wrong password") { createSheetPreview(requiresPassword: true) { $0.errorMessage = "That password is not right." } }
#Preview("Creating") { createSheetPreview(requiresPassword: true) { $0.isWorking = true } }
