#if os(macOS)
    import DesignSystem
    import SwiftUI

    /// One label and value row in a Mac inspector's grouped form, the value selectable and
    /// trailing like Finder's Get Info.
    struct MacInfoRow: View {
        let label: String
        let value: String
        /// Nil keeps the system's secondary value colour.
        var valueColor: Color?

        init(_ label: String, _ value: String, valueColor: Color? = nil) {
            self.label = label
            self.value = value
            self.valueColor = valueColor
        }

        var body: some View {
            LabeledContent(label) {
                Text(value)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                    .foregroundStyle(valueColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
            }
        }
    }

    #Preview("Info rows") {
        Form {
            MacInfoRow("Kind", "Folder")
            MacInfoRow("Expires", "Nov 21, 2026", valueColor: Color.attention)
            MacInfoRow("Expired", "Nov 17, 2026", valueColor: Color.negativeText)
        }
        .formStyle(.grouped)
        .previewCanvas(.inspector)
    }
#endif
