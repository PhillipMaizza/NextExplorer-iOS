import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

private typealias Metrics = UserDetailMetrics

/// Assign or edit a user volume: label, access mode, and (for a new volume) a drill-down
/// admin directory picker. Presented from `UserDetailView`'s Volumes tab.
struct VolumeAssignSheet: View {
    @Bindable var store: StoreOf<UserManagementFeature>
    @Environment(\.dismiss) private var dismiss
    @Dependency(\.filesClient) private var filesClient

    @State private var listing: AdminDirectoryListing?
    @State private var isBrowsing = false
    @State private var browseError: String?
    /// The directory currently being listed; `nil` is the server's volume root. Bound to a
    /// `.task(id:)` so drilling in or out cancels any in flight listing before the next one,
    /// since rapid taps otherwise race and the slower one wins.
    @State private var browsePath: String?

    private var sheet: UserManagementFeature.VolumeSheetState? { store.volumeSheet }

    var body: some View {
        DSDynamicHeightSheet(maxHeightFraction: Metrics.volumeSheetMaxHeightFraction) {
            VStack(alignment: .leading, spacing: Metrics.volumeSheetSpacing) {
                DSSheetHeader(
                    icon: IconKit.drive,
                    title: sheet?.isEditing == true ? L10n.UserDetail.volumeSheetTitleEdit : L10n.UserDetail.volumeSheetTitleNew,
                    closeAccessibilityLabel: L10n.Common.close,
                    onClose: { dismiss() }
                )

                if let sheet {
                    if let error = sheet.errorMessage {
                        DSErrorCard(error)
                    }

                    LabeledField(L10n.UserDetail.volumeSheetLabelField, uppercased: false) {
                        DSTextField(L10n.UserDetail.volumeSheetLabelPlaceholder, text: Binding(
                            get: { store.volumeSheet?.label ?? "" },
                            set: { store.send(.volumeLabelChanged($0)) }
                        ))
                        .autocorrectionDisabled()
                    }

                    VStack(alignment: .leading, spacing: .space4) {
                        DSFieldLabel(L10n.UserDetail.volumeSheetAccessMode, uppercased: false)
                        DSSegmentedControl(
                            options: ShareAccessMode.allCases,
                            selection: Binding(
                                get: { store.volumeSheet?.accessMode ?? .readwrite },
                                set: { store.send(.volumeAccessModeChanged($0)) }
                            ),
                            label: { $0.title }
                        )
                    }

                    VStack(alignment: .leading, spacing: .space4) {
                        DSFieldLabel(L10n.UserDetail.volumeSheetDirectory, uppercased: false)
                        if sheet.isEditing {
                            Text(sheet.selectedPath)
                                .type(.body2(.regular))
                                .foregroundStyle(Color.secondaryDS)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .roundedFieldStyle()
                        } else {
                            directoryBrowser(selectedPath: sheet.selectedPath)
                        }
                    }
                }
            }
            .padding(.horizontal, Metrics.volumeSheetSpacing)
            .padding(.vertical, Metrics.volumeSheetSpacing)
        } footer: {
            DSSheetFooter {
                DSButton(
                    (sheet?.isEditing ?? false) ? L10n.UserDetail.volumeSheetSaveEdit : L10n.UserDetail.volumeSheetSaveNew,
                    style: .primary,
                    isLoading: sheet?.isSubmitting ?? false
                ) {
                    store.send(.volumeSubmitTapped)
                }
                .disabled(!(sheet?.isSubmitEnabled ?? false))
            }
        }
        .task(id: browsePath) {
            guard sheet?.isEditing == false else { return }
            await loadDirectories(path: browsePath)
        }
    }

    @ViewBuilder
    private func directoryBrowser(selectedPath: String) -> some View {
        VStack(alignment: .leading, spacing: .space8) {
            if let listing {
                HStack(spacing: .space8) {
                    Text(listing.current).type(.caption(.regular), style: .tertiary).lineLimit(1).truncationMode(.head)
                    Spacer()
                    if let parent = listing.parent {
                        Button {
                            browsePath = parent
                        } label: {
                            IconKit.levelUp.resizable().scaledToFit()
                                .foregroundStyle(Color.accent)
                                .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
                        }
                        .buttonStyle(DSHapticButtonStyle())
                        .accessibilityLabel(L10n.UserDetail.directoryPickerGoUp)
                    }
                }
                Button {
                    store.send(.volumePathSelected(listing.current))
                } label: {
                    rowLabel(L10n.UserDetail.directoryPickerUseThis, isSelected: selectedPath == listing.current, icon: IconKit.checkmark)
                }
                .buttonStyle(DSHapticButtonStyle())

                ForEach(listing.directories) { directory in
                    HStack(spacing: .space8) {
                        Button {
                            store.send(.volumePathSelected(directory.path))
                        } label: {
                            rowLabel(directory.name, isSelected: selectedPath == directory.path, icon: IconKit.folder)
                        }
                        .buttonStyle(DSHapticButtonStyle())
                        Spacer()
                        Button {
                            browsePath = directory.path
                        } label: {
                            IconKit.chevronRight.resizable().scaledToFit()
                                .foregroundStyle(Color.tertiaryDS)
                                .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
                        }
                        .buttonStyle(DSHapticButtonStyle())
                        .accessibilityLabel(L10n.UserDetail.directoryPickerOpen(directory.name))
                    }
                }
            } else if isBrowsing {
                DSSpinner().frame(maxWidth: .infinity).padding(.vertical, .space8)
            } else if let browseError {
                Text(browseError).type(.body3(.semibold), style: .error)
            }
        }
        .padding(Metrics.cardPadding)
        .background(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius).fill(Color.backgroundSecondary))
    }

    private func rowLabel(_ text: String, isSelected: Bool, icon: Image) -> some View {
        HStack(spacing: .space8) {
            icon.resizable().scaledToFit()
                .foregroundStyle(isSelected ? Color.accent : Color.secondaryDS)
                .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
            Text(text)
                .type(.body3(.regular), style: isSelected ? .link : .primary(for: .label))
                .lineLimit(1)
        }
        .padding(.vertical, .space4)
        .contentShape(Rectangle())
    }

    private func loadDirectories(path: String?) async {
        isBrowsing = true
        browseError = nil
        defer { isBrowsing = false }
        do {
            let next = try await filesClient.browseAdminDirectories(store.serverURL, path)
            guard !Task.isCancelled else { return }
            listing = next
        } catch {
            guard !Task.isCancelled else { return }
            browseError = (error as? FilesClientError)?.userMessage ?? L10n.UserDetail.directoryPickerFailed
        }
    }
}
