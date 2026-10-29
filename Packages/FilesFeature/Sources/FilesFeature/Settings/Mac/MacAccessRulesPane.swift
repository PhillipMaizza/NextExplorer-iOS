#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let padding: CGFloat = .space24
        static let spacing: CGFloat = .space12
        static let recursiveColumnWidth: CGFloat = 150
        static let permissionColumnWidth: CGFloat = 150
    }

    /// The Folder Access Rules pane: the rules as an editable table, with add and remove under
    /// it and the save button below.
    struct MacAccessRulesPane: View {
        let store: StoreOf<AccessRulesFeature>
        @State private var selection: AccessRule.ID?

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
                    ProgressView()
                }
            }
            .onAppear { store.send(.onAppear) }
        }

        private var content: some View {
            VStack(alignment: .leading, spacing: Metrics.spacing) {
                MacSettingsNote(L10n.AccessRules.subtitle)
                VStack(spacing: 0) {
                    table
                    Divider()
                    addRemoveBar
                }
                .border(Color(nsColor: .separatorColor))
                if let error = store.errorMessage ?? store.phase.errorMessage {
                    Text(error).foregroundStyle(Color.negativeText)
                }
            }
            .padding(Metrics.padding)
        }

        private var table: some View {
            Table(store.drafts, selection: $selection) {
                TableColumn(L10n.AccessRules.pathLabel) { rule in
                    TextField(L10n.AccessRules.pathPlaceholder, text: Binding(
                        get: { store.drafts[id: rule.id]?.path ?? "" },
                        set: { store.send(.pathChanged(id: rule.id, $0)) }
                    ))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                }
                TableColumn(L10n.AccessRules.recursive) { rule in
                    Toggle(L10n.AccessRules.recursive, isOn: Binding(
                        get: { store.drafts[id: rule.id]?.isRecursive ?? false },
                        set: { store.send(.recursiveToggled(id: rule.id, $0)) }
                    ))
                    .labelsHidden()
                }
                .width(Metrics.recursiveColumnWidth)
                TableColumn(L10n.MacSettings.permission) { rule in
                    Picker(L10n.MacSettings.permission, selection: Binding(
                        get: { store.drafts[id: rule.id]?.permission ?? .readWrite },
                        set: { store.send(.permissionChanged(id: rule.id, $0)) }
                    )) {
                        ForEach(AccessRule.Permission.allCases, id: \.self) { permission in
                            Text(Self.permissionLabel(permission)).tag(permission)
                        }
                    }
                    .labelsHidden()
                }
                .width(Metrics.permissionColumnWidth)
            }
            .overlay {
                if store.drafts.isEmpty, store.phase != .loading {
                    VStack(spacing: .space4) {
                        Text(L10n.AccessRules.empty)
                        Text(L10n.AccessRules.emptyHint).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }

        /// The Mac's add and remove pair under a list.
        private var addRemoveBar: some View {
            HStack(spacing: 0) {
                Button { store.send(.addRuleTapped) } label: {
                    Image(systemName: "plus").frame(width: 24, height: 20)
                }
                .accessibilityLabel(L10n.AccessRules.addRule)
                Divider().frame(height: 16)
                Button {
                    if let selection {
                        store.send(.removeRule(id: selection))
                        self.selection = nil
                    }
                } label: {
                    Image(systemName: "minus").frame(width: 24, height: 20)
                }
                .disabled(selection == nil)
                .accessibilityLabel(L10n.AccessRules.remove)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, .space4)
            .padding(.vertical, .space2)
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
