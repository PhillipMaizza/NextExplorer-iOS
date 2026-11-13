import ComposableArchitecture
import SwiftUI

#Preview {
    OfflineTabView(
        store: Store(initialState: OfflineTabFeature.State()) {
            OfflineTabFeature()
        } withDependencies: {
            $0.localDownloadStore.list = { _ in
                [
                    LocalDownload(
                        url: URL(fileURLWithPath: "/tmp/Documents/Downloads/report.pdf"),
                        fileName: "report.pdf",
                        size: 245_000,
                        modifiedDate: Date()
                    ),
                    LocalDownload(
                        url: URL(fileURLWithPath: "/tmp/Caches/Downloads/vacation.jpg"),
                        fileName: "vacation.jpg",
                        size: 2_400_000,
                        modifiedDate: Date().addingTimeInterval(-86400)
                    ),
                ]
            }
        },
        offlineStore: Store(initialState: OfflineManageFeature.State()) { OfflineManageFeature() }
    )
}

#Preview("Empty") {
    OfflineTabView(
        store: Store(initialState: OfflineTabFeature.State()) {
            OfflineTabFeature()
        } withDependencies: {
            $0.localDownloadStore.list = { _ in [] }
        },
        offlineStore: Store(initialState: OfflineManageFeature.State()) { OfflineManageFeature() }
    )
}

#Preview("Error") {
    OfflineTabView(
        store: Store(initialState: OfflineTabFeature.State()) {
            OfflineTabFeature()
        } withDependencies: {
            $0.localDownloadStore.list = { _ in throw NSError(domain: "test", code: 1) }
        },
        offlineStore: Store(initialState: OfflineManageFeature.State()) { OfflineManageFeature() }
    )
}
