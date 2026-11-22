#if os(macOS)
    import SwiftUI

    private enum Constants {
        static let rowMinHeight: CGFloat = 52
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
                .padding(.horizontal, .size40)
                .padding(.top, .space24)
                .padding(.bottom, .space32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(Typography.TextType.body2(.regular).font())
            .toggleStyle(.macSwitch)
        }
    }

    public struct MacFormGroup<Content: View>: View {
        private let title: String?
        private let content: () -> Content

        public init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
            self.title = title
            self.content = content
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: .space8) {
                if let title {
                    MacFormGroupTitle(title)
                }
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
                .background(Constants.groupShape.fill(Color.macRow))
                .clipShape(Constants.groupShape)
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
            .frame(minHeight: Constants.rowMinHeight)
        }
    }

    public extension MacFormRow where Label == Text {
        init(_ title: String, @ViewBuilder control: @escaping () -> Control) {
            self.init(label: { Text(title) }, control: control)
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
        }
        .background(Color.macCard)
        .previewCanvas(.settingsPane)
    }
#endif
