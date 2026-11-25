#if os(macOS)
    import DesignSystem
    import SwiftUI

    struct MacValueRow: View {
        let title: String
        let value: String

        init(_ title: String, _ value: String) {
            self.title = title
            self.value = value
        }

        var body: some View {
            MacFormRow(title) {
                Text(value)
                    .type(.body2(.regular), style: .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }

    #Preview("Value row") {
        MacFormGroup {
            MacValueRow("Server", "files.example.com")
        }
        .padding()
        .previewCanvasWidth(.settingsPane)
    }
#endif
