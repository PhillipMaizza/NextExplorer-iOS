#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    struct MacShareAccessField: View {
        let isDirectory: Bool
        let choice: Binding<ShareAccessChoice>
        let permissions: Binding<SharePermissions>

        var body: some View {
            MacLabeledField(L10n.CreateShare.peopleCan) {
                MacFormGroup {
                    ForEach(
                        ShareAccessChoice.options(isDirectory: isDirectory, current: choice.wrappedValue),
                        id: \.self
                    ) {
                        option in
                        MacChoiceRow(
                            option.title,
                            subtitle: option.hint(isDirectory: isDirectory),
                            icon: option.icon,
                            isSelected: option == choice.wrappedValue
                        ) { choice.wrappedValue = option }
                    }
                    if choice.wrappedValue == .custom {
                        ForEach(SharePermissionSwitch.options(isDirectory: isDirectory), id: \.self) { item in
                            MacToggleOption(item.title, icon: item.icon, isOn: permissions[dynamicMember: item.keyPath])
                                .padding(.leading, MacChoiceRow.nestedIndent)
                        }
                    }
                }
            }
        }
    }

    enum SharePermissionSwitch: CaseIterable, Hashable {
        case download
        case delete
        case createFolders
        case createFiles
        case upload

        static func options(isDirectory: Bool) -> [Self] {
            isDirectory ? allCases : [.download]
        }

        var keyPath: WritableKeyPath<SharePermissions, Bool> {
            switch self {
            case .download: \.canDownload
            case .delete: \.canDelete
            case .createFolders: \.canCreateFolders
            case .createFiles: \.canCreateFiles
            case .upload: \.canUpload
            }
        }

        var title: String {
            switch self {
            case .download: L10n.Common.download
            case .delete: L10n.CreateShare.permissionDelete
            case .createFolders: L10n.CreateShare.permissionCreateFolders
            case .createFiles: L10n.CreateShare.permissionCreateFiles
            case .upload: L10n.CreateShare.permissionUpload
            }
        }

        var icon: Image {
            switch self {
            case .download: IconKit.macDownload
            case .delete: IconKit.macTrash
            case .createFolders: IconKit.macNewFolder
            case .createFiles: IconKit.macNewFile
            case .upload: IconKit.macUpload
            }
        }
    }

    struct MacShareVersionsOptions: View {
        let permissions: Binding<SharePermissions>

        var body: some View {
            MacToggleOption(
                L10n.CreateShare.versionsVisible,
                info: L10n.CreateShare.versionsVisibleHint,
                isOn: permissions.showsVersions
            )
            MacToggleOption(
                L10n.CreateShare.versionsDownload,
                icon: IconKit.macClock,
                isOn: permissions.canDownloadVersions
            )
            .disabled(!permissions.wrappedValue.showsVersions)
            .opacity(permissions.wrappedValue.showsVersions ? 1 : .opacityHalf)
        }
    }

    extension Share {
        var accessChoice: ShareAccessChoice {
            ShareAccessChoice(accessMode: accessMode, permissions: permissions)
        }
    }

    extension ShareAccessChoice {
        var title: String {
            switch self {
            case .viewOnly: L10n.CreateShare.accessViewOnly
            case .canDownload: L10n.CreateShare.accessCanDownload
            case .canEdit: L10n.CreateShare.accessCanEdit
            case .custom: L10n.EditShare.custom
            }
        }

        func hint(isDirectory: Bool) -> String {
            switch self {
            case .viewOnly: L10n.CreateShare.accessViewOnlyHint
            case .canDownload: L10n.CreateShare.accessCanDownloadHint
            case .canEdit: isDirectory ? L10n.CreateShare.accessCanEditHint : L10n.CreateShare.accessCanEditFileHint
            case .custom: L10n.CreateShare.accessCustomHint
            }
        }

        var icon: Image {
            switch self {
            case .viewOnly: IconKit.macEye
            case .canDownload: IconKit.macDownload
            case .canEdit: IconKit.macPencil
            case .custom: IconKit.macSliders
            }
        }
    }

    private struct AccessFieldPreview: View {
        @State var choice: ShareAccessChoice
        @State var permissions = SharePermissions(canDelete: false)
        let isDirectory: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: .space16) {
                MacShareAccessField(isDirectory: isDirectory, choice: $choice, permissions: $permissions)
                MacFormGroup { MacShareVersionsOptions(permissions: $permissions) }
            }
            .padding(.space24)
            .previewCanvasWidth(.sheet)
            .background(Color.macCard)
        }
    }

    #Preview("Folder, Custom") {
        AccessFieldPreview(choice: .custom, isDirectory: true)
    }

    #Preview("File, dark") {
        AccessFieldPreview(choice: .canDownload, isDirectory: false)
            .preferredColorScheme(.dark)
    }
#endif
