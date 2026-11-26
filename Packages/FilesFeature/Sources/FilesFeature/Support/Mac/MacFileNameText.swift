#if os(macOS)
    import AppStorageKeys
    import DesignSystem
    import SwiftUI

    struct MacFileNameText: View {
        let name: String
        let isDirectory: Bool
        @AppStorage(AppStorageKeys.showFilenameExtensions) private var shouldShowFilenameExtensions = true
        @Environment(\.backgroundProminence) private var prominence

        var body: some View {
            Text(displayFileName(name, isDirectory: isDirectory, showExtension: shouldShowFilenameExtensions))
                .fontWeight(prominence == .increased ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    #Preview {
        VStack(alignment: .leading, spacing: .space8) {
            MacFileNameText(name: "report.pdf", isDirectory: false)
            MacFileNameText(name: "Projects.v2", isDirectory: true)
            MacFileNameText(name: ".env", isDirectory: false)
        }
        .padding(.space16)
    }
#endif
