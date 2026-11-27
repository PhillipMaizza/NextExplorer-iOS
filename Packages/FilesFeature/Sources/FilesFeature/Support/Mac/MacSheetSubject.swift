#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    struct MacSheetSubject: View {
        let name: String
        let isDirectory: Bool
        let location: String
        let label: Binding<String>

        var body: some View {
            HStack(spacing: .space12) {
                MacItemTile(
                    kind: (name as NSString).pathExtension.lowercased(),
                    isDirectory: isDirectory,
                    size: .size40
                )
                VStack(alignment: .leading, spacing: .space4) {
                    MacTextField(L10n.CreateShare.sectionLabel, text: label, prompt: name)
                    if !location.isEmpty {
                        Text(PersonalSpace.trail(location))
                            .type(.caption(.regular), style: .secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
            }
        }
    }

    #Preview("Subjects") {
        VStack(alignment: .leading, spacing: .space16) {
            MacSheetSubject(name: "Website", isDirectory: true, location: "Files/Developer", label: .constant(""))
            MacSheetSubject(
                name: "README.md",
                isDirectory: false,
                location: "Files/Developer/bcn-holidays-ics",
                label: .constant("Docs")
            )
            MacSheetSubject(name: "Files", isDirectory: true, location: "", label: .constant(""))
        }
        .padding(.space24)
        .previewCanvasWidth(.sheet)
        .background(Color.macCard)
    }
#endif
