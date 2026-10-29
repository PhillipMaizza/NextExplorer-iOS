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

    /// A Settings pane in the System Settings style: rounded grouped sections, each row a label
    /// with its value or control at the trailing edge, notes as section footers.
    struct MacSettingsPane<Content: View>: View {
        @ViewBuilder let content: () -> Content

        var body: some View {
            Form {
                content()
            }
            .formStyle(.grouped)
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
                ForEach(lines, id: \.self) { Text($0) }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    /// A row title with a secondary line under it, for grouped rows that need explaining.
    struct MacRowTitle: View {
        let title: String
        let subtitle: String

        var body: some View {
            VStack(alignment: .leading, spacing: Metrics.noteSpacing) {
                Text(title)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
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
                        ProgressView().controlSize(.small)
                    }
                    Button(title, action: action)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!isEnabled)
                }
                .padding(.horizontal, Metrics.horizontalPadding)
                .padding(.vertical, Metrics.verticalPadding / 2)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
            }
        }
    }

    extension View {
        func macSettingsSaveBar(_ title: String, isSaving: Bool, isEnabled: Bool, action: @escaping () -> Void) -> some View {
            modifier(MacSettingsSaveBar(title: title, isSaving: isSaving, isEnabled: isEnabled, action: action))
        }
    }

    /// A number field with its stepper, like the Mac's own preference panes.
    struct MacNumberStepper: View {
        let value: Int
        let range: ClosedRange<Int>
        let step: Int
        var unit: String?
        let onChange: (Int) -> Void

        private var binding: Binding<Int> {
            Binding(get: { value }, set: { onChange(min(max($0, range.lowerBound), range.upperBound)) })
        }

        var body: some View {
            HStack(spacing: .space4) {
                TextField("", value: binding, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 64)
                Stepper("", value: binding, in: range, step: step)
                    .labelsHidden()
                if let unit {
                    Text(unit).foregroundStyle(.secondary)
                }
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
        .frame(width: 640, height: 300)
    }
#endif
