import ComposableArchitecture
import DesignSystem
import Localization
import SwiftUI

private struct DownloadRenameSheet: ViewModifier {
    let store: StoreOf<OfflineTabFeature>

    private var renameItemBinding: Binding<LocalDownload?> {
        Binding(get: { store.renameItem }, set: {
            if $0 == nil {
                store.send(.renameCancelled)
            }
        })
    }

    func body(content: Content) -> some View {
        content
            .dsSheet(item: renameItemBinding) { item in
                NameInputSheet(
                    icon: IconKit.rename,
                    title: L10n.Browse.renameTitle,
                    placeholder: L10n.Browse.renameNamePlaceholder,
                    confirmTitle: L10n.Common.save,
                    initialName: item.fileName,
                    isBusy: false,
                    onConfirm: { store.send(.renameConfirmed($0)) },
                    onCancel: { store.send(.renameCancelled) }
                )
            }
    }
}

extension View {
    func downloadRenameSheet(store: StoreOf<OfflineTabFeature>) -> some View {
        modifier(DownloadRenameSheet(store: store))
    }
}

#Preview("Rename") {
    var state = OfflineTabFeature.State()
    state.renameItem = LocalDownload(
        url: URL(fileURLWithPath: "/tmp/report.pdf"),
        fileName: "report.pdf",
        size: 1_200_000,
        modifiedDate: Date()
    )
    return Color.clear.downloadRenameSheet(store: Store(initialState: state) { OfflineTabFeature() })
}
