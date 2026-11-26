#if os(macOS)
    import SwiftUI

    private enum Constants {
        static let groupShape = RoundedRectangle(cornerRadius: .radiusMedium, style: .continuous)
    }

    public struct MacFormPage<Content: View>: View {
        private let spacing: CGFloat
        private let content: () -> Content

        public init(spacing: CGFloat = .space24, @ViewBuilder content: @escaping () -> Content) {
            self.spacing = spacing
            self.content = content
        }

        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    content()
                }
                .padding(.horizontal, .space40)
                .padding(.top, .space24)
                .padding(.bottom, .space32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .type(.body2(.regular))
            .toggleStyle(.macSwitch)
        }
    }

    public struct MacFormGroup<Content: View>: View {
        private let title: String?
        private let info: [String]
        private let content: () -> Content

        public init(_ title: String? = nil, info: [String] = [], @ViewBuilder content: @escaping () -> Content) {
            self.title = title
            self.info = info
            self.content = content
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: .space8) {
                if let title {
                    HStack(spacing: .zero) {
                        MacFormGroupTitle(title)
                        if !info.isEmpty {
                            MacInfoButton(lines: info)
                        }
                    }
                }
                MacFormRows(content: content)
                    .background(Constants.groupShape.fill(Color.macRow))
                    .clipShape(Constants.groupShape)
            }
        }
    }

    public struct MacFormRows<Content: View>: View {
        private let content: () -> Content

        public init(@ViewBuilder content: @escaping () -> Content) {
            self.content = content
        }

        public var body: some View {
            VStack(spacing: .zero) {
                Group(subviews: content()) { subviews in
                    ForEach(Array(subviews.enumerated()), id: \.element.id) { index, subview in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.macLine)
                                .frame(height: .borderWidthHairline)
                        }
                        subview
                    }
                }
            }
        }
    }

    public struct MacFormGroupTitle: View {
        private let title: String

        public init(_ title: String) {
            self.title = title
        }

        public var body: some View {
            Text(title)
                .type(.body2(.semibold), style: .secondary)
                .padding(.horizontal, .space4)
                .accessibilityAddTraits(.isHeader)
        }
    }

    public struct MacFormFootnote: View {
        private let lines: [String]

        public init(_ lines: String...) {
            self.lines = lines
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: .space4) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .type(.body3(.regular), style: .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, .space4)
        }
    }

    public struct MacFormRow<Label: View, Control: View>: View {
        private let label: () -> Label
        private let control: () -> Control

        public init(@ViewBuilder label: @escaping () -> Label, @ViewBuilder control: @escaping () -> Control) {
            self.label = label
            self.control = control
        }

        public var body: some View {
            HStack(spacing: .space12) {
                label()
                    .frame(maxWidth: .infinity, alignment: .leading)
                control()
            }
            .padding(.horizontal, .space16)
            .padding(.vertical, .space8)
            .macMinHeight(.formRow)
        }
    }

    public extension MacFormRow where Label == Text {
        init(_ title: String, @ViewBuilder control: @escaping () -> Control) {
            self.init(label: { Text(title) }, control: control)
        }
    }

    public struct MacFormRowTitle: View {
        private let title: String
        private let subtitle: String

        public init(title: String, subtitle: String) {
            self.title = title
            self.subtitle = subtitle
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: .space2) {
                Text(title)
                Text(subtitle).type(.body3(.regular), style: .secondary)
            }
        }
    }

    public struct MacFormSheetRow<Content: View>: View {
        private let title: String
        private let content: () -> Content

        public init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
            self.title = title
            self.content = content
        }

        public var body: some View {
            LabeledContent(title) {
                VStack(alignment: .leading, spacing: .space8) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, .space8)
        }
    }

    public struct MacControlNote: View {
        private let lines: [String]

        public init(_ lines: String...) {
            self.lines = lines
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: .space2) {
                ForEach(lines, id: \.self) { Text($0).type(.body3(.regular), style: .secondary) }
            }
        }
    }

    #Preview("Form page") {
        MacFormPage {
            MacFormGroup("General") {
                MacFormRow("Show Hidden Files") {
                    Toggle("Show Hidden Files", isOn: .constant(true)).labelsHidden()
                }
                MacFormRow("Language") {
                    Text(verbatim: "System Default").foregroundStyle(Color.macChromeSecondary)
                }
            }
            MacFormFootnote("Applies to every window.", "Changes take effect at once.")
        }
        .background(Color.macCard)
        .previewCanvas(.settingsPane)
    }

    #Preview("Sheet rows") {
        Form {
            MacFormSheetRow("Name") {
                MacTextField("Name", text: .constant(""), prompt: "A name")
                MacControlNote("Shown to everyone with the link.")
            }
            MacFormSheetRow("Expiry") {
                MacFormRowTitle(title: "90 days", subtitle: "Renew any time.")
            }
        }
        .formStyle(.columns)
        .padding()
        .previewCanvasWidth(.dialog)
        .background(Color.macCard)
    }
#endif
