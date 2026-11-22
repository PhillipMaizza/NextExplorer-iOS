#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let headerTop: CGFloat = .space32
        static let verticalPadding: CGFloat = .space24
        static let rowSpacing: CGFloat = .space8
        static let noteSpacing: CGFloat = .space2
        static let cardInset: CGFloat = .space16
        static let headerInset: CGFloat = .size40
        static let groupedFormInset: CGFloat = .size20
    }

    struct MacSettingsPaneCard<Content: View>: View {
        let title: String
        let subtitle: String?
        @ViewBuilder let content: () -> Content

        var body: some View {
            VStack(alignment: .leading, spacing: .zero) {
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

    /// A Settings pane in the System Settings style: rounded grouped sections, each row a label
    /// with its value or control at the trailing edge, notes as section footers.
    struct MacSettingsPane<Content: View>: View {
        @ViewBuilder let content: () -> Content

        var body: some View {
            Form {
                content()
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .font(Typography.TextType.body2(.regular).font())
            .padding(.horizontal, Metrics.groupedFormInset)
        }
    }

    /// A grouped section footer: explanatory lines in the secondary color.
    struct MacSectionFooter: View {
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

    /// A label column form, as Mac dialogs (sheets) lay out their fields: right aligned labels ending
    /// in a colon, with the checkboxes, pickers and buttons in a column beside them.
    struct MacSettingsForm<Content: View>: View {
        @ViewBuilder let content: () -> Content

        var body: some View {
            Form {
                content()
            }
            .formStyle(.columns)
            .font(Typography.TextType.body2(.regular).font())
            .padding(.horizontal, Metrics.headerInset)
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
                ForEach(lines, id: \.self) { Text($0).type(.body3(.regular), style: .secondary) }
            }
        }
    }

    /// The save button a pane's edits wait for, pinned under the form at the trailing edge, with
    /// Return as its shortcut.
    struct MacSettingsSaveBar: ViewModifier {
        let title: String
        let isSaving: Bool
        let isEnabled: Bool
        let action: () -> Void

        func body(content: Content) -> some View {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: Metrics.rowSpacing) {
                    Spacer()
                    if isSaving {
                        MacSpinner()
                    }
                    Button(title, action: action)
                        .buttonStyle(.macDS(.primary))
                        .keyboardShortcut(.defaultAction)
                        .disabled(!isEnabled)
                }
                .padding(.horizontal, Metrics.headerInset)
                .padding(.vertical, Metrics.cardInset)
                .background(Color.macCard)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.macLine)
                        .frame(height: .borderWidthHairline)
                }
            }
        }
    }

    extension View {
        func macSettingsSaveBar(
            _ title: String,
            isSaving: Bool,
            isEnabled: Bool,
            action: @escaping () -> Void
        ) -> some View {
            modifier(MacSettingsSaveBar(title: title, isSaving: isSaving, isEnabled: isEnabled, action: action))
        }
    }

    /// A number field with its stepper, like the Mac's own preference panes.
    struct MacNumberStepper: View {
        /// Spoken for both the field and the stepper, which show no label of their own.
        let label: String
        let value: Int
        let range: ClosedRange<Int>
        let step: Int
        let onChange: (Int) -> Void

        private var binding: Binding<Int> {
            Binding(get: { value }, set: { onChange(min(max($0, range.lowerBound), range.upperBound)) })
        }

        var body: some View {
            HStack(spacing: .space4) {
                TextField(label, value: binding, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: .size64)
                Stepper(label, value: binding, in: range, step: step)
                    .labelsHidden()
            }
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
        .previewCanvas(.settingsPane)
    }

    #Preview("Pane card") {
        MacSettingsPaneCard(title: "Thumbnails", subtitle: "Control how previews are generated.") {
            MacSettingsPane {
                Section("General") {
                    Toggle("Show Hidden Files", isOn: .constant(true))
                }
            }
        }
        .background(Color.macChrome)
        .previewCanvas(.settingsPane)
    }

    #Preview("Pane card, no subtitle") {
        MacSettingsPaneCard(title: "General", subtitle: nil) {
            MacSettingsPane {
                Section("General") {
                    Toggle("Show Hidden Files", isOn: .constant(true))
                }
            }
        }
        .background(Color.macChrome)
        .previewCanvas(.settingsPane)
    }
#endif
