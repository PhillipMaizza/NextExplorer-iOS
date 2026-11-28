#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let gridColumnWidth: CGFloat = .size72
        static let numericWidth: CGFloat = 84
    }

    /// Permissions as a native Mac dialog: owner and group, the read, write and execute checkboxes
    /// with the numeric mode, then Save, which applies whichever of the two changed.
    struct MacPermissionsSheet: View {
        @Bindable var store: StoreOf<PermissionsFeature>
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            MacFormSheet(
                title: L10n.Permissions.titleFor(store.item.name),
                confirmTitle: L10n.Common.save,
                isConfirmEnabled: store.isDirty,
                isWorking: store.isSavingMode || store.isSavingOwnership,
                errorMessage: store.actionError ?? store.phase.errorMessage,
                layout: .stacked,
                onCancel: { dismiss() },
                onConfirm: { store.send(.saveTapped) }
            ) {
                if store.phase == .loading, store.permissions == nil {
                    MacSpinner().frame(maxWidth: .infinity)
                } else if store.permissions == nil, store.phase.errorMessage != nil {
                    Button(L10n.Common.retry) { store.send(.onAppear) }
                        .buttonStyle(.macDS(.secondary))
                } else {
                    ownership
                    accessGrid
                    numericRow
                    if store.item.isDirectory {
                        Toggle(L10n.Permissions.applyToEnclosed, isOn: $store.recursive.sending(\.recursiveChanged))
                            .toggleStyle(.macCheckbox)
                    }
                }
            }
            .task { store.send(.onAppear) }
        }

        private var accessGrid: some View {
            Grid(horizontalSpacing: .zero, verticalSpacing: .space8) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(PermissionRight.allCases, id: \.self) { right in
                        Text(right.macTitle(isDirectory: store.item.isDirectory))
                            .type(.caption(.semibold), style: .secondary)
                            .frame(width: Metrics.gridColumnWidth)
                    }
                }
                ForEach(PermissionScope.allCases, id: \.self) { scope in
                    GridRow {
                        Text(scope.macTitle)
                            .type(.body2(.regular))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(PermissionRight.allCases, id: \.self) { right in
                            Toggle(isOn: Binding(
                                get: { store.grid[scope]?.contains(right) ?? false },
                                set: { _ in store.send(.toggle(scope, right)) }
                            )) { EmptyView() }
                                .toggleStyle(.macCheckbox)
                                .frame(width: Metrics.gridColumnWidth)
                                .accessibilityLabel(L10n.Common.pair(
                                    scope.macTitle,
                                    right.macTitle(isDirectory: store.item.isDirectory)
                                ))
                        }
                    }
                }
            }
            .padding(.horizontal, .space16)
            .padding(.vertical, .space12)
            .macGroupedRows()
        }

        private var numericRow: some View {
            HStack(spacing: .space8) {
                Text(L10n.Permissions.numericLabel).type(.body3(.regular), style: .secondary)
                MacTextField(
                    L10n.Permissions.numericLabel,
                    text: $store.numericDraft.sending(\.numericChanged)
                )
                .monospaced()
                .multilineTextAlignment(.center)
                .frame(width: Metrics.numericWidth)
                Text(FilePermissions.symbolicString(from: store.grid))
                    .type(.body3(.semibold), style: .secondary)
                    .monospaced()
            }
        }

        private var ownership: some View {
            VStack(alignment: .leading, spacing: .space4) {
                ownershipFields
                MacFieldError(message: store.ownershipError)
            }
        }

        private var ownershipFields: some View {
            HStack(spacing: .space12) {
                MacLabeledField(L10n.Permissions.fieldOwner) {
                    MacTextField(L10n.Permissions.fieldOwner, text: $store.ownerDraft.sending(\.ownerDraftChanged))
                        .autocorrectionDisabled()
                }
                MacLabeledField(L10n.Permissions.fieldGroup) {
                    MacTextField(L10n.Permissions.fieldGroup, text: $store.groupDraft.sending(\.groupDraftChanged))
                        .autocorrectionDisabled()
                }
            }
        }
    }

    @MainActor
    private func permissionsPreview(
        _ permissions: FilePermissions?,
        isDirectory: Bool = false,
        ownerDraft: String? = nil
    ) -> some View {
        let item = FileItem(
            name: isDirectory ? "Projects" : "report.pdf",
            path: "Files/Developer",
            dateModified: Date(),
            size: 1_024,
            kind: isDirectory ? "directory" : "pdf"
        )
        var state = PermissionsFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            item: item
        )
        if let permissions {
            state.permissions = permissions
            state.grid = permissions.grid
            state.numericDraft = permissions.octalString
            state.ownerDraft = permissions.owner
            state.groupDraft = permissions.group
        }
        if let ownerDraft {
            state.ownerDraft = ownerDraft
        }
        return MacPermissionsSheet(store: Store(initialState: state) { PermissionsFeature() } withDependencies: {
            $0.filesClient = .previewValue
        })
    }

    #Preview("File") {
        permissionsPreview(FilePermissions(
            path: "report.pdf",
            mode: 0o100_644,
            owner: "phillip",
            group: "staff",
            uid: 501,
            gid: 20,
            isDirectory: false
        ))
    }

    #Preview("Folder") {
        permissionsPreview(
            FilePermissions(
                path: "Projects",
                mode: 0o40_755,
                owner: "phillip",
                group: "staff",
                uid: 501,
                gid: 20,
                isDirectory: true
            ),
            isDirectory: true
        )
    }

    #Preview("Invalid owner") {
        permissionsPreview(
            FilePermissions(
                path: "report.pdf",
                mode: 0o100_644,
                owner: "phillip",
                group: "staff",
                uid: 501,
                gid: 20,
                isDirectory: false
            ),
            ownerDraft: "-phillip"
        )
    }

    #Preview("Loading") {
        permissionsPreview(nil)
    }
#endif
