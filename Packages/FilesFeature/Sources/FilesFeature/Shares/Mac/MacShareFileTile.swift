#if os(macOS)
    import CoreModels
    import DesignSystem
    import SwiftUI

    struct MacShareFileTile: View {
        let share: Share
        let name: String
        let serverURL: URL
        var sizedItem: FileItem?
        var onNeedsSize: () -> Void = {}

        private var needsSize: Bool {
            share.fileItem().map(DocumentThumbnailStore.isDocumentKind) ?? false
        }

        var body: some View {
            Group {
                if let file = sizedItem ?? share.fileItem() {
                    MacFileTile(item: file, serverURL: serverURL)
                } else {
                    MacItemTile(name: name, isDirectory: share.isDirectory)
                }
            }
            .onAppear {
                if sizedItem == nil, needsSize {
                    onNeedsSize()
                }
            }
        }
    }

    #Preview("Share file tile") {
        MacShareFileTile(
            share: Share.previewSharedByMe[0],
            name: Share.previewSharedByMe[0].displayName,
            serverURL: sharedPreviewServerURL
        )
        .padding(.space16)
    }
#endif
