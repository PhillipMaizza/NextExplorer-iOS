#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    struct MacSheetSubject: View {
        let name: String
        let isDirectory: Bool
        let location: String

        var body: some View {
            HStack(spacing: .space12) {
                MacItemTile(
                    kind: (name as NSString).pathExtension.lowercased(),
                    isDirectory: isDirectory,
                    size: .size40
                )
                VStack(alignment: .leading, spacing: .zero) {
                    Text(name)
                        .type(.body2(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !location.isEmpty {
                        Text(PathTrail.text(location))
                            .type(.caption(.regular), style: .secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    #Preview("Subjects") {
        VStack(alignment: .leading, spacing: .space16) {
            MacSheetSubject(name: "Website", isDirectory: true, location: "Files/Developer")
            MacSheetSubject(name: "README.md", isDirectory: false, location: "Files/Developer/bcn-holidays-ics")
            MacSheetSubject(name: "Files", isDirectory: true, location: "")
        }
        .padding(.space24)
        .previewCanvasWidth(.sheet)
        .background(Color.macCard)
    }
#endif
