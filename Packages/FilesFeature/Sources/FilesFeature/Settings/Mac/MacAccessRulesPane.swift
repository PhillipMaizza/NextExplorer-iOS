#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let permissionWidth: CGFloat = 130
    }

    /// The Folder Access Rules pane: one grouped row per rule, Add Rule under them, and the save
    /// button below.
    struct MacAccessRulesPane: View {
        let store: StoreOf<AccessRulesFeature>

        var body: some View {
            Group {
                if store.isUnavailable {
                    MacSettingsForm { MacSettingsNote(L10n.AccessRules.unavailable) }
                } else {
                    content.macSettingsSaveBar(
                        L10n.AccessRules.saveButton,
                        isSaving: store.isSaving,
                        isEnabled: store.isSaveEnabled
                    ) { store.send(.saveTapped) }
                }
            }
            .overlay {
                if store.phase == .loading, store.loaded == nil, !store.isUnavailable {
                    ProgressView().controlSize(.small)
                }
            }
            .onAppear { store.send(.onAppear) }
        }

        private var content: some View {
            MacSettingsPane {
                Section {
                    if store.drafts.isEmpty, store.phase != .loading {
                        MacRowTitle(title: L10n.AccessRules.empty, subtitle: L10n.AccessRules.emptyHint)
                    }
                    ForEach(store.drafts) { rule in
                        ruleRow(rule)
                    }
                    HStack {
                        Spacer()
                        Button(L10n.AccessRules.addRule) { store.send(.addRuleTapped, animation: .default) }
                    }
                } footer: {
                    MacSectionFooter(L10n.AccessRules.subtitle)
                }
                if let error = store.errorMessage ?? store.phase.errorMessage {
                    Text(error).foregroundStyle(Color.negativeText)
                }
            }
        }

        /// One rule on a row: its path, whether it reaches subfolders, the permission, and remove.
        private func ruleRow(_ rule: AccessRule) -> some View {
            HStack(spacing: .space12) {
                TextField(L10n.AccessRules.pathLabel, text: Binding(
                    get: { store.drafts[id: rule.id]?.path ?? "" },
                    set: { store.send(.pathChanged(id: rule.id, $0)) }
                ), prompt: Text(L10n.AccessRules.pathPlaceholder))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Toggle(L10n.AccessRules.recursive, isOn: Binding(
                    get: { store.drafts[id: rule.id]?.isRecursive ?? false },
                    set: { store.send(.recursiveToggled(id: rule.id, $0)) }
                ))
                .toggleStyle(.checkbox)
                .fixedSize()
                Picker(L10n.MacSettings.permission, selection: Binding(
                    get: { store.drafts[id: rule.id]?.permission ?? .readWrite },
                    set: { store.send(.permissionChanged(id: rule.id, $0)) }
                )) {
                    ForEach(AccessRule.Permission.allCases, id: \.self) { permission in
                        Text(Self.permissionLabel(permission)).tag(permission)
                    }
                }
                .labelsHidden()
                .frame(width: Metrics.permissionWidth)
                Button(role: .destructive) {
                    store.send(.removeRule(id: rule.id), animation: .default)
                } label: {
                    IconKit.removeCircle
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.negativeText)
                .accessibilityLabel(L10n.AccessRules.remove)
            }
        }

        static func permissionLabel(_ permission: AccessRule.Permission) -> String {
            switch permission {
            case .readWrite: L10n.AccessRules.permissionReadWrite
            case .readOnly: L10n.AccessRules.permissionReadOnly
            case .hidden: L10n.AccessRules.permissionHidden
            }
        }
    }

    #Preview("Access rules") {
        var state = AccessRulesFeature.State(serverURL: URL(string: "https://files.example.com") ?? URL(fileURLWithPath: "/"))
        let rules = [
            AccessRule(id: "1", path: "Documents/Reports", isRecursive: true, permission: .readOnly),
            AccessRule(id: "2", path: "Private", isRecursive: false, permission: .hidden),
        ]
        state.loaded = rules
        state.drafts = IdentifiedArray(uniqueElements: rules)
        state.phase = .loaded
        return MacAccessRulesPane(store: Store(initialState: state) { AccessRulesFeature() })
            .frame(width: 580, height: 420)
    }
#endif
