#if os(iOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    struct ShareAccessOptions: View {
        let isDirectory: Bool
        var isWritable = true
        let choice: Binding<ShareAccessChoice>
        let permissions: Binding<SharePermissions>

        var body: some View {
            EditShareChoices(
                options: ShareAccessChoice.options(
                    isDirectory: isDirectory,
                    current: choice.wrappedValue,
                    isWritable: isWritable
                ),
                selection: choice.wrappedValue,
                title: \.title,
                hint: { [isDirectory] in $0.hint(isDirectory: isDirectory) },
                icon: \.icon,
                onSelect: { choice.wrappedValue = $0 }
            )
            if choice.wrappedValue == .custom {
                ForEach(SharePermissionSwitch.options(isDirectory: isDirectory), id: \.self) { item in
                    DSToggleRow(title: item.title, icon: item.icon, isOn: permissions[dynamicMember: item.keyPath])
                }
            }
        }
    }

    struct ShareVersionsToggles: View {
        let permissions: Binding<SharePermissions>

        var body: some View {
            DSToggleRow(
                title: L10n.CreateShare.versionsVisible,
                subtitle: L10n.CreateShare.versionsVisibleHint,
                icon: IconKit.restore,
                isOn: permissions.showsVersions
            )
            DSToggleRow(
                title: L10n.CreateShare.versionsDownload,
                icon: IconKit.download,
                isOn: permissions.canDownloadVersions
            )
            .disabled(!permissions.wrappedValue.showsVersions)
            .opacity(permissions.wrappedValue.showsVersions ? 1 : .opacityHalf)
        }
    }

    private struct ShareAccessPreview: View {
        @State var choice: ShareAccessChoice
        @State var permissions = SharePermissions(canDelete: false)
        let isDirectory: Bool
        var isWritable = true

        var body: some View {
            List {
                Section { ShareAccessOptions(
                    isDirectory: isDirectory,
                    isWritable: isWritable,
                    choice: $choice,
                    permissions: $permissions
                ) }
                Section { ShareVersionsToggles(permissions: $permissions) }
            }
        }
    }

    #Preview("Folder, Custom") {
        ShareAccessPreview(choice: .custom, isDirectory: true)
    }

    #Preview("File, dark") {
        ShareAccessPreview(choice: .canDownload, isDirectory: false)
            .preferredColorScheme(.dark)
    }

    #Preview("Folder, read only path") {
        ShareAccessPreview(choice: .canDownload, isDirectory: true, isWritable: false)
    }
#endif
