#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    struct MacShareAccessField: View {
        let isDirectory: Bool
        var isWritable = true
        let choice: Binding<ShareAccessChoice>
        let permissions: Binding<SharePermissions>

        var body: some View {
            MacLabeledField(L10n.CreateShare.peopleCan) {
                MacFormGroup {
                    ForEach(
                        ShareAccessChoice.options(
                            isDirectory: isDirectory,
                            current: choice.wrappedValue,
                            isWritable: isWritable
                        ),
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

    private struct AccessFieldPreview: View {
        @State var choice: ShareAccessChoice
        @State var permissions = SharePermissions(canDelete: false)
        let isDirectory: Bool
        var isWritable = true

        var body: some View {
            VStack(alignment: .leading, spacing: .space16) {
                MacShareAccessField(
                    isDirectory: isDirectory,
                    isWritable: isWritable,
                    choice: $choice,
                    permissions: $permissions
                )
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

    #Preview("Folder, read only path") {
        AccessFieldPreview(choice: .canDownload, isDirectory: true, isWritable: false)
    }
#endif
