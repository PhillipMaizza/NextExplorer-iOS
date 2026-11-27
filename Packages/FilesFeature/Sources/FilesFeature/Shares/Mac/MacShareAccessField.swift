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
                        indented(L10n.Common.download, isOn: permissions.canDownload)
                        if isDirectory {
                            indented(L10n.CreateShare.permissionDelete, isOn: permissions.canDelete)
                            indented(L10n.CreateShare.permissionCreateFolders, isOn: permissions.canCreateFolders)
                            indented(L10n.CreateShare.permissionCreateFiles, isOn: permissions.canCreateFiles)
                            indented(L10n.CreateShare.permissionUpload, isOn: permissions.canUpload)
                        }
                    }
                }
            }
        }

        private func indented(_ title: String, isOn: Binding<Bool>) -> some View {
            MacToggleOption(title, isOn: isOn)
                .padding(.leading, MacChoiceRow.textIndent - .space16)
        }
    }

    struct MacShareVersionsOptions: View {
        let permissions: Binding<SharePermissions>

        var body: some View {
            MacToggleOption(
                L10n.CreateShare.versionsVisible,
                subtitle: L10n.CreateShare.versionsVisibleHint,
                isOn: permissions.showsVersions
            )
            MacToggleOption(L10n.CreateShare.versionsDownload, isOn: permissions.canDownloadVersions)
                .padding(.leading, MacChoiceRow.textIndent - .space16)
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
        var popupOptions: [ShareAccessChoice] {
            self == .custom ? Self.allCases : [.viewOnly, .canDownload, .canEdit]
        }

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
            case .viewOnly: IconKit.eye
            case .canDownload: IconKit.menuDownload
            case .canEdit: IconKit.pencil
            case .custom: IconKit.sliders
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
