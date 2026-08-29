import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

private enum Constants {
    static let contentSpacing: CGFloat = .space24
    static let sectionSpacing: CGFloat = .space8
    static let horizontalPadding: CGFloat = .space24
    static let verticalPadding: CGFloat = .space24
    static let cardCornerRadius: CGFloat = .radiusCard
    static let cardPadding: CGFloat = .space12
    static let checkboxSize: CGFloat = .iconSmall
    static let maxHeightFraction: CGFloat = 0.9
}

/// The "Permissions" sheet — `GET /api/permissions/*` to view, `POST /api/permissions/chmod`
/// and `/chown` to change. A 3×3 read/write/execute grid maps to the octal mode; owner and
/// group are free-text (chown usually needs root, so a failure is shown, not hidden).
struct PermissionsSheet: View {
    @Bindable var store: StoreOf<PermissionsFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DSDynamicHeightSheet(maxHeightFraction: Constants.maxHeightFraction) {
            VStack(alignment: .leading, spacing: Constants.contentSpacing) {
                DSSheetHeader(
                    icon: IconKit.lock,
                    title: store.item.name,
                    closeAccessibilityLabel: L10n.Common.close,
                    onClose: { dismiss() }
                )
                content
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
        } footer: {
            if store.permissions != nil {
                footer
            }
        }
        .task { store.send(.onAppear) }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: Constants.contentSpacing) {
            if let loadError = store.loadError {
                DSErrorCard(loadError)
                DSButton(L10n.Common.retry, style: .secondary) {
                    store.send(.onAppear)
                }
            }

            if store.isLoading && store.permissions == nil {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, .space24)
            } else if store.permissions != nil {
                ownershipSection
                modeSection
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        DSSheetFooter {
            VStack(spacing: .space8) {
                if let actionError = store.actionError {
                    DSErrorCard(actionError)
                }
                DSButton(L10n.Permissions.applyOwnership, style: .secondary, isLoading: store.isSavingOwnership) {
                    store.send(.applyOwnershipTapped)
                }
                .disabled(!store.isOwnershipDirty)

                DSButton(L10n.Permissions.applyPermissions, style: .primary, isLoading: store.isSavingMode) {
                    store.send(.applyModeTapped)
                }
                .disabled(!store.isModeDirty)
            }
        }
    }

    // MARK: Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
            DSFieldLabel(L10n.Permissions.sectionMode)

            VStack(alignment: .leading, spacing: .space12) {
                grid
                Divider()
                HStack {
                    Text(L10n.Permissions.numericLabel).type(.body3(.regular), style: .secondary)
                    Spacer()
                    Text(store.octalString)
                        .type(.body2(.bold), style: .primary(for: .label))
                        .monospaced()
                }
                if store.item.isDirectory {
                    DSToggleRow(
                        title: L10n.Permissions.applyToEnclosed,
                        icon: IconKit.folderFill,
                        isOn: $store.recursive.sending(\.recursiveChanged)
                    )
                }
            }
            .padding(Constants.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Constants.cardCornerRadius).fill(Color.backgroundSecondary))
        }
    }

    private var grid: some View {
        Grid(alignment: .center, horizontalSpacing: .space8, verticalSpacing: .space16) {
            GridRow {
                Color.clear.frame(width: 0, height: 0).gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(Self.rights, id: \.0) { _, title in
                    Text(title)
                        .type(.caption(.semibold), style: .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Self.scopes, id: \.0) { scope, title in
                GridRow {
                    Text(title)
                        .type(.body3(.regular), style: .primary(for: .label))
                        .gridColumnAlignment(.leading)
                    ForEach(Self.rights, id: \.0) { right, _ in
                        checkbox(scope, right)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func checkbox(_ scope: PermissionScope, _ right: PermissionRight) -> some View {
        let isOn = store.grid[scope]?.contains(right) ?? false
        return Button {
            store.send(.toggle(scope, right))
        } label: {
            DSSelectionIndicator(isSelected: isOn, size: Constants.checkboxSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(DSHapticButtonStyle())
        .hapticFeedback(.selection, trigger: isOn)
    }

    // MARK: Ownership

    private var ownershipSection: some View {
        VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
            DSFieldLabel(L10n.Permissions.sectionOwnership)

            VStack(alignment: .leading, spacing: .space4) {
                DSFieldLabel(L10n.Permissions.fieldOwner, uppercased: false)
                DSTextField(
                    L10n.Permissions.fieldOwner,
                    text: $store.ownerDraft.sending(\.ownerDraftChanged)
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            VStack(alignment: .leading, spacing: .space4) {
                DSFieldLabel(L10n.Permissions.fieldGroup, uppercased: false)
                DSTextField(
                    L10n.Permissions.fieldGroup,
                    text: $store.groupDraft.sending(\.groupDraftChanged)
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            Text(L10n.Permissions.ownershipNote).type(.body3(.regular), style: .tertiary)
        }
    }

    // MARK: Column/row labels

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

// MARK: - Previews

private let previewServerURL = URL(string: "https://cloud.example.com")!

@MainActor
private func permissionsPreview(
    _ state: PermissionsFeature.State,
    configureClient: @Sendable (inout FilesClient) -> Void = { _ in }
) -> some View {
    var client = FilesClient.previewValue
    configureClient(&client)
    return Color.clear.sheet(isPresented: .constant(true)) {
        PermissionsSheet(
            store: Store(initialState: state) {
                PermissionsFeature()
            } withDependencies: {
                $0.filesClient = client
            }
        )
    }
}

private let previewFile = FileItem(name: "report.pdf", path: "Documents", dateModified: Date(), size: 1_024, kind: "pdf")
private let previewFolder = FileItem(name: "Projects", path: "", dateModified: Date(), size: 0, kind: "directory")

private func previewState(
    item: FileItem = previewFile,
    permissions: FilePermissions? = nil,
    actionError: String? = nil
) -> PermissionsFeature.State {
    var state = PermissionsFeature.State(serverURL: previewServerURL, item: item)
    if let permissions {
        state.permissions = permissions
        state.grid = permissions.grid
        state.ownerDraft = permissions.owner
        state.groupDraft = permissions.group
    }
    state.actionError = actionError
    return state
}

private let filePermissions = FilePermissions(
    path: "Documents/report.pdf", mode: 0o100_644, owner: "phillip", group: "staff", uid: 501, gid: 20, isDirectory: false
)
private let folderPermissions = FilePermissions(
    path: "Projects", mode: 0o40_755, owner: "phillip", group: "staff", uid: 501, gid: 20, isDirectory: true
)

#Preview("File") {
    permissionsPreview(previewState(permissions: filePermissions)) {
        $0.fetchPermissions = { _, _ in filePermissions }
    }
}

#Preview("Directory") {
    permissionsPreview(previewState(item: previewFolder, permissions: folderPermissions)) {
        $0.fetchPermissions = { _, _ in folderPermissions }
    }
}

#Preview("Load error") {
    permissionsPreview(previewState()) {
        $0.fetchPermissions = { _, _ in
            throw FilesClientError.serverMessage(statusCode: 403, message: "You don't have access to this path.")
        }
    }
}

#Preview("Ownership denied") {
    permissionsPreview(
        previewState(
            permissions: filePermissions,
            actionError: "Permission denied. Changing ownership typically requires root/admin privileges."
        )
    ) {
        $0.fetchPermissions = { _, _ in filePermissions }
        $0.changeOwnership = { _, _, _, _ in
            throw FilesClientError.serverMessage(
                statusCode: 403,
                message: "Permission denied. Changing ownership typically requires root/admin privileges."
            )
        }
    }
}
