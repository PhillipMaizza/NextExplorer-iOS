#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let horizontalPadding: CGFloat = .space32
        static let verticalPadding: CGFloat = .space24
        static let rowSpacing: CGFloat = .space8
        static let noteSpacing: CGFloat = .space2
    }

    /// A Settings tab laid out like a native Mac preferences pane: right aligned labels ending
    /// in a colon, with the checkboxes, pickers and buttons in a column beside them.
    struct MacSettingsForm<Content: View>: View {
        @ViewBuilder let content: () -> Content

        var body: some View {
            Form {
                content()
            }
            .formStyle(.columns)
            .padding(.horizontal, Metrics.horizontalPadding)
            .padding(.vertical, Metrics.verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// One labeled group of a `MacSettingsForm`, its controls stacked in the value column.
    struct MacSettingsRow<Content: View>: View {
        let title: String
        @ViewBuilder let content: () -> Content

        init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
            self.title = title
            self.content = content
        }

        var body: some View {
            LabeledContent(L10n.MacSettings.labelFormat(title)) {
                VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, Metrics.rowSpacing)
        }
    }

    /// Explanatory text under a control, in the secondary color.
    struct MacSettingsNote: View {
        let lines: [String]

        init(_ lines: String...) {
            self.lines = lines
        }

        var body: some View {
            VStack(alignment: .leading, spacing: Metrics.noteSpacing) {
                ForEach(lines, id: \.self) { Text($0) }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    #Preview("Form") {
        MacSettingsForm {
            MacSettingsRow("General") {
                Toggle("Show Hidden Files", isOn: .constant(true))
                Toggle("Show Filename Extensions", isOn: .constant(false))
                MacSettingsNote("Applies to every window.")
            }
        }
        .frame(width: 640, height: 300)
    }
#endif
