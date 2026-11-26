#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let rowHeight: CGFloat = .size64
        static let permissionWidth: CGFloat = 150
    }

    struct MacAccessRulesPane: View {
        let store: StoreOf<AccessRulesFeature>

        private var errorMessage: String? {
            store.errorMessage ?? store.phase.errorMessage
        }

        private var showsEmptyGuide: Bool {
            !store.isUnavailable && store.loaded != nil && store.drafts.isEmpty && errorMessage == nil
        }

        var body: some View {
            Group {
                if showsEmptyGuide {
                    emptyGuide
                } else {
                    MacFormPage {
                        if store.isUnavailable {
                            MacNote(L10n.AccessRules.unavailable, kind: .info)
                        } else if store.phase == .loading, store.loaded == nil {
                            MacSpinner()
                                .frame(maxWidth: .infinity)
                        } else {
                            if !store.drafts.isEmpty {
                                MacFormGroup {
                                    ForEach(store.drafts) { rule in
                                        ruleRow(rule)
                                    }
                                }
                            }
                            if let errorMessage {
                                MacNote(errorMessage, kind: .error)
                            }
                        }
                    }
                }
            }
            .disabled(store.isSaving)
            .onAppear { store.send(.onAppear) }
        }

        private var emptyGuide: some View {
            MacEmptyGuide(title: L10n.EmptyGuide.accessRulesTitle) {
                MacEmptyGuideTile(icon: IconKit.accessRules)
            } detail: {
                MacEmptyGuideBullet(
                    icon: IconKit.macLock,
                    text: L10n.EmptyGuide.accessRulesReadOnly(L10n.AccessRules.permissionReadOnly)
                )
                MacEmptyGuideBullet(
                    icon: IconKit.macEyeSlash,
                    text: L10n.EmptyGuide.accessRulesHidden(L10n.AccessRules.permissionHidden)
                )
                Button(L10n.AccessRules.addRule) { store.send(.addRuleTapped, animation: DSMotion.listDiff) }
                    .buttonStyle(.macDS(.primary))
                    .padding(.top, .space4)
            }
        }

        private func ruleRow(_ rule: AccessRule) -> some View {
            let permission = store.drafts[id: rule.id]?.permission ?? .readWrite
            return MacFormRow {
                MacTextField(
                    L10n.AccessRules.pathLabel,
                    text: Binding(
                        get: { store.drafts[id: rule.id]?.path ?? "" },
                        set: { store.send(.pathChanged(id: rule.id, $0)) }
                    ),
                    prompt: L10n.AccessRules.pathPlaceholder
                )
                .autocorrectionDisabled()
            } control: {
                HStack(spacing: .space12) {
                    MacPopup(
                        L10n.MacSettings.permission,
                        valueLabel: Self.permissionLabel(permission),
                        selection: Binding(
                            get: { permission },
                            set: { store.send(.permissionChanged(id: rule.id, $0)) }
                        ),
                        shouldFillWidth: true
                    ) {
                        ForEach(AccessRule.Permission.allCases, id: \.self) { option in
                            Text(Self.permissionLabel(option)).tag(option)
                        }
                    }
                    .frame(width: Metrics.permissionWidth)
                    Toggle(L10n.AccessRules.recursive, isOn: Binding(
                        get: { store.drafts[id: rule.id]?.isRecursive ?? false },
                        set: { store.send(.recursiveToggled(id: rule.id, $0)) }
                    ))
                    .toggleStyle(.macCheckbox)
                    .fixedSize()
                    Button(L10n.AccessRules.remove, role: .destructive) {
                        store.send(.removeRule(id: rule.id), animation: DSMotion.listDiff)
                    }
                    .buttonStyle(.macDS(.secondary, size: .small))
                    .fixedSize()
                }
            }
            .frame(minHeight: Metrics.rowHeight)
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
        var state = AccessRulesFeature
            .State(serverURL: URL(string: "https://files.example.com") ?? URL(fileURLWithPath: "/"))
        let rules = [
            AccessRule(id: "1", path: "Documents/Reports", isRecursive: true, permission: .readOnly),
            AccessRule(id: "2", path: "Private", isRecursive: false, permission: .hidden),
        ]
        state.loaded = rules
        state.drafts = IdentifiedArray(uniqueElements: rules)
        state.phase = .loaded
        return MacAccessRulesPane(store: Store(initialState: state) { AccessRulesFeature() })
            .previewCanvas(.settingsWindow)
    }
#endif
