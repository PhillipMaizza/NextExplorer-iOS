#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import FolderPickerFeature
    import Localization
    import SwiftUI

    struct MacVLCLocalCopy: View {
        let item: FileItem
        let serverURL: URL
        let onReady: (URL) -> Void

        @Dependency(\.filesClient) private var filesClient
        @State private var errorMessage: String?
        @State private var attempt = 0

        init(item: FileItem, serverURL: URL, errorMessage: String? = nil, onReady: @escaping (URL) -> Void) {
            self.item = item
            self.serverURL = serverURL
            self.onReady = onReady
            _errorMessage = State(initialValue: errorMessage)
        }

        static func isTooLarge(_ item: FileItem) -> Bool {
            item.size > MacPeekContent.Kind.byteLimit
        }

        var body: some View {
            if Self.isTooLarge(item) {
                MacNoPreviewPage(item: item, source: .remote(item, serverURL: serverURL))
            } else {
                download
            }
        }

        private var download: some View {
            ZStack {
                Color.black
                if let errorMessage {
                    PreviewErrorView(message: errorMessage) {
                        self.errorMessage = nil
                        attempt += 1
                    }
                } else {
                    DSSpinner()
                }
            }
            .task(id: attempt) {
                guard errorMessage == nil else { return }
                do {
                    let fileURL = try await filesClient.previewFile(serverURL, item)
                    guard !Task.isCancelled else { return }
                    onReady(fileURL)
                } catch {
                    noteSessionExpiry(error)
                    guard !Task.isCancelled else { return }
                    errorMessage = (error as? FilesClientError)?.userMessage ?? L10n.TextPreview.loadFailed
                }
            }
        }
    }

    #Preview("Downloading") {
        MacVLCLocalCopy(
            item: FileItem(name: "clip.webm", path: "", dateModified: .distantPast, size: 3_667_214, kind: "webm"),
            serverURL: URL(fileURLWithPath: "/"),
            onReady: { _ in }
        )
        .frame(width: 480, height: 320)
    }

    #Preview("Too large") {
        MacVLCLocalCopy(
            item: FileItem(name: "film.mkv", path: "", dateModified: .distantPast, size: 4_000_000_000, kind: "mkv"),
            serverURL: URL(fileURLWithPath: "/"),
            onReady: { _ in }
        )
        .frame(width: 480, height: 320)
    }

    #Preview("Failed") {
        MacVLCLocalCopy(
            item: FileItem(name: "clip.webm", path: "", dateModified: .distantPast, size: 3_667_214, kind: "webm"),
            serverURL: URL(fileURLWithPath: "/"),
            errorMessage: L10n.TextPreview.loadFailed,
            onReady: { _ in }
        )
        .frame(width: 480, height: 320)
    }
#endif
