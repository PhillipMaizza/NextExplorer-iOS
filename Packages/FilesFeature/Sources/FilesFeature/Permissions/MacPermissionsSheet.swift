#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import Localization
    import SwiftUI

    private enum Metrics {
        static let gridColumnWidth: CGFloat = 70
    }

    /// Permissions as a native Mac dialog: ownership fields with their own Apply, the
    /// read / write / execute checkboxes with the octal mode, then Close and Apply Permissions.
    struct MacPermissionsSheet: View {
        @Bindable var store: StoreOf<PermissionsFeature>
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            MacFormSheet(
                title: store.item.name,
                confirmTitle: L10n.Permissions.applyPermissions,
                isConfirmEnabled: store.isModeDirty,
                isWorking: store.isSavingMode || store.isSavingOwnership,
                errorMessage: store.actionError ?? store.phase.errorMessage,
                cancelTitle: L10n.Common.close,
                onCancel: { dismiss() },
                onConfirm: { store.send(.applyModeTapped) }
            ) {
                if store.phase == .loading, store.permissions == nil {
                    ProgressView().frame(maxWidth: .infinity)
                } else if store.permissions == nil, store.phase.errorMessage != nil {
                    Button(L10n.Common.retry) { store.send(.onAppear) }
                } else {
                    ownershipRows
                    modeRows
                }
            }
            .task { store.send(.onAppear) }
        }

        @ViewBuilder
        private var ownershipRows: some View {
            MacSettingsRow(L10n.Permissions.fieldOwner) {
                TextField(L10n.Permissions.fieldOwner, text: $store.ownerDraft.sending(\.ownerDraftChanged))
                    .labelsHidden()
                    .autocorrectionDisabled()
            }
            MacSettingsRow(L10n.Permissions.fieldGroup) {
                TextField(L10n.Permissions.fieldGroup, text: $store.groupDraft.sending(\.groupDraftChanged))
                    .labelsHidden()
                    .autocorrectionDisabled()
                MacSettingsNote(L10n.Permissions.ownershipNote)
                Button(L10n.Permissions.applyOwnership) { store.send(.applyOwnershipTapped) }
                    .disabled(!store.isOwnershipDirty || store.isSavingOwnership)
            }
        }

        @ViewBuilder
        private var modeRows: some View {
            MacSettingsRow(L10n.Permissions.sectionMode) {
                Grid(alignment: .leading, horizontalSpacing: .space12, verticalSpacing: .space8) {
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        ForEach(Self.rights, id: \.0) { _, title in
                            Text(title).foregroundStyle(.secondary).frame(width: Metrics.gridColumnWidth)
                        }
                    }
                    ForEach(Self.scopes, id: \.0) { scope, title in
                        GridRow {
                            Text(title)
                            ForEach(Self.rights, id: \.0) { right, rightTitle in
                                Toggle(rightTitle, isOn: Binding(
                                    get: { store.grid[scope]?.contains(right) ?? false },
                                    set: { _ in store.send(.toggle(scope, right)) }
                                ))
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .frame(width: Metrics.gridColumnWidth)
                                .accessibilityLabel("\(title) \(rightTitle)")
                            }
                        }
                    }
                }
            }
            MacSettingsRow(L10n.Permissions.numericLabel) {
                Text(store.octalString).monospaced().textSelection(.enabled)
                if store.item.isDirectory {
                    Toggle(L10n.Permissions.applyToEnclosed, isOn: $store.recursive.sending(\.recursiveChanged))
                }
            }
        }

        private static var scopes: [(PermissionScope, String)] {
            [
                (.owner, L10n.Permissions.scopeOwner),
                (.group, L10n.Permissions.scopeGroup),
                (.others, L10n.Permissions.scopeOthers),
            ]
        }

        private static var rights: [(PermissionRight, String)] {
            [
                (.read, L10n.Permissions.rightRead),
                (.write, L10n.Permissions.rightWrite),
                (.execute, L10n.Permissions.rightExecute),
            ]
        }
    }
#endif
