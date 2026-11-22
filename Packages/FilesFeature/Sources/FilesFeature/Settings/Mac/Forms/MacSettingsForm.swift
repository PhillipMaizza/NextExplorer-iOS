#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let headerTop: CGFloat = .space32
        static let rowSpacing: CGFloat = .space8
        static let noteSpacing: CGFloat = .space2
        static let cardInset: CGFloat = .space16
        static let headerInset: CGFloat = .size40
    }

    struct MacSettingsPaneCard<Content: View, Tools: View>: View {
        let title: String
        let subtitle: String?
        @ViewBuilder let content: () -> Content
        @ViewBuilder let tools: () -> Tools

        init(
            title: String,
            subtitle: String?,
            @ViewBuilder content: @escaping () -> Content,
            @ViewBuilder tools: @escaping () -> Tools
        ) {
            self.title = title
            self.subtitle = subtitle
            self.content = content
            self.tools = tools
        }

        var body: some View {
            VStack(alignment: .leading, spacing: .zero) {
                HStack(spacing: .space16) {
                    VStack(alignment: .leading, spacing: .space8) {
                        Text(title)
                            .type(.display)
                            .accessibilityAddTraits(.isHeader)
                        if let subtitle {
                            Text(subtitle)
                                .type(.body2(.regular), style: .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: .zero)
                    tools()
                }
                .padding(.horizontal, Metrics.headerInset)
                .padding(.top, Metrics.headerTop)
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .macCard()
            .padding([.trailing, .bottom], Metrics.cardInset)
        }
    }

    extension MacSettingsPaneCard where Tools == EmptyView {
        init(title: String, subtitle: String?, @ViewBuilder content: @escaping () -> Content) {
            self.init(title: title, subtitle: subtitle, content: content) { EmptyView() }
        }
    }

    /// A row title with a secondary line under it, for grouped rows that need explaining.
    struct MacRowTitle: View {
        let title: String
        let subtitle: String

        var body: some View {
            VStack(alignment: .leading, spacing: Metrics.noteSpacing) {
                Text(title)
                Text(subtitle).type(.body3(.regular), style: .secondary)
            }
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
            LabeledContent(title) {
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
                ForEach(lines, id: \.self) { Text($0).type(.body3(.regular), style: .secondary) }
            }
        }
    }

    struct MacPaneSaveButton: View {
        let title: String
        let isSaving: Bool
        let isEnabled: Bool
        let action: () -> Void

        var body: some View {
            HStack(spacing: Metrics.rowSpacing) {
                if isSaving {
                    MacSpinner()
                }
                Button(title, action: action)
                    .buttonStyle(.macDS(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isEnabled)
            }
        }
    }

    #Preview("Sheet rows") {
        Form {
            MacSettingsRow("Name") {
                MacTextField("Name", text: .constant(""), prompt: "A name")
                MacSettingsNote("Shown to everyone with the link.")
            }
        }
        .formStyle(.columns)
        .padding()
        .previewCanvasWidth(.dialog)
        .background(Color.macCard)
    }

    #Preview("Pane card") {
        MacSettingsPaneCard(title: "Thumbnails", subtitle: "Control how previews are generated.") {
            MacFormPage {
                MacFormGroup("General") {
                    MacSwitchRow("Show Hidden Files", isOn: .constant(true))
                }
            }
        } tools: {
            MacPaneSaveButton(title: "Save Changes", isSaving: false, isEnabled: true) {}
        }
        .background(Color.macChrome)
        .previewCanvas(.settingsPane)
    }

    #Preview("Pane card, no subtitle") {
        MacSettingsPaneCard(title: "General", subtitle: nil) {
            MacFormPage {
                MacFormGroup("General") {
                    MacSwitchRow("Show Hidden Files", isOn: .constant(true))
                }
            }
        }
        .background(Color.macChrome)
        .previewCanvas(.settingsPane)
    }
#endif
