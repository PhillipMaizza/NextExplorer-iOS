import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Metrics {
    static let contentSpacing: CGFloat = .space16
    static let horizontalPadding: CGFloat = .space16
    static let ruleSpacing: CGFloat = .space12
    static let emptyPadding: CGFloat = .space32
}

/// Admin-only editor for the server's path access rules, pushed from the Settings admin
/// section. Mirrors the web client's `SettingsAccessControl.vue`.
struct AccessRulesView: View {
    @Bindable var store: StoreOf<AccessRulesFeature>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
                Text(L10n.AccessRules.subtitle)
                    .type(.body3(.regular), style: .secondary)

                if store.isUnavailable {
                    DSErrorCard(L10n.AccessRules.unavailable)
                } else {
                    if store.drafts.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.drafts) { rule in
                            ruleCard(rule)
                        }
                    }

                    DSButton(L10n.AccessRules.addRule, icon: IconKit.plus, style: .secondary) {
                        store.send(.addRuleTapped, animation: .default)
                    }

                    if let error = store.errorMessage ?? store.phase.errorMessage {
                        DSErrorCard(error)
                    }

                    DSButton(L10n.AccessRules.saveButton, style: .primary, isLoading: store.isSaving) {
                        store.send(.saveTapped)
                    }
                    .disabled(!store.isSaveEnabled)
                    .padding(.top, .space4)
                }
            }
            .padding(.horizontal, Metrics.horizontalPadding)
            .padding(.vertical, Metrics.contentSpacing)
        }
        .backgroundGradient()
        .navigationTitle(L10n.AccessRules.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if store.phase == .loading, store.loaded == nil, !store.isUnavailable {
                DSSpinner()
            }
        }
        .onAppear { store.send(.onAppear) }
    }

    private var emptyState: some View {
        VStack(spacing: .space8) {
            Text(L10n.AccessRules.empty).type(.body2(.regular), style: .secondary)
            Text(L10n.AccessRules.emptyHint).type(.body3(.regular), style: .tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metrics.emptyPadding)
        .background(RoundedRectangle(cornerRadius: .radiusCard).fill(Color.backgroundSecondary))
    }

    private func ruleCard(_ rule: AccessRule) -> some View {
        VStack(alignment: .leading, spacing: Metrics.ruleSpacing) {
            VStack(alignment: .leading, spacing: .space4) {
                DSFieldLabel(L10n.AccessRules.pathLabel, uppercased: false)
                DSTextField(
                    L10n.AccessRules.pathPlaceholder,
                    text: Binding(
                        get: { store.drafts[id: rule.id]?.path ?? "" },
                        set: { store.send(.pathChanged(id: rule.id, $0)) }
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            DSToggleRow(
                title: L10n.AccessRules.recursive,
                icon: IconKit.folder,
                isOn: Binding(
                    get: { store.drafts[id: rule.id]?.isRecursive ?? false },
                    set: { store.send(.recursiveToggled(id: rule.id, $0)) }
                )
            )

            DSSegmentedControl(
                options: AccessRule.Permission.allCases,
                selection: Binding(
                    get: { store.drafts[id: rule.id]?.permission ?? .readWrite },
                    set: { store.send(.permissionChanged(id: rule.id, $0)) }
                ),
                label: Self.permissionLabel
            )

            HStack {
                Spacer()
                Button(role: .destructive) {
                    store.send(.removeRule(id: rule.id), animation: .default)
                } label: {
                    HStack(spacing: .space4) {
                        IconKit.delete
                            .resizable().scaledToFit()
                            .frame(width: .iconXSmall, height: .iconXSmall)
                        Text(L10n.AccessRules.remove).type(.body2(.semibold))
                    }
                    .foregroundStyle(Color.negative)
                }
                .buttonStyle(DSHapticButtonStyle())
            }
        }
        .padding(.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: .radiusCard).fill(Color.backgroundSecondary))
    }

    private static func permissionLabel(_ permission: AccessRule.Permission) -> String {
        switch permission {
        case .readWrite: L10n.AccessRules.permissionReadWrite
        case .readOnly: L10n.AccessRules.permissionReadOnly
        case .hidden: L10n.AccessRules.permissionHidden
        }
    }
}

private extension AccessRulesFeature.State {
    static func preview(
        rules: [AccessRule],
        loaded: Bool = true,
        error: String? = nil
    ) -> Self {
        var state = AccessRulesFeature.State(serverURL: URL(string: "https://files.example.com")!)
        if loaded {
            state.loaded = rules
        }
        state.phase = loaded ? .loaded : .idle
        state.drafts = IdentifiedArray(uniqueElements: rules)
        state.errorMessage = error
        return state
    }
}

#Preview("Rules") {
    NavigationStack {
        AccessRulesView(
            store: Store(
                initialState: .preview(rules: [
                    AccessRule(id: "1", path: "Documents/Reports", isRecursive: true, permission: .readOnly),
                    AccessRule(id: "2", path: "Private", isRecursive: false, permission: .hidden),
                ])
            ) { AccessRulesFeature() }
        )
    }
}

#Preview("Empty") {
    NavigationStack {
        AccessRulesView(
            store: Store(initialState: .preview(rules: [AccessRule]())) { AccessRulesFeature() }
        )
    }
}
