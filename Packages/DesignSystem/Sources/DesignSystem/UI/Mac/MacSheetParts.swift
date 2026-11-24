#if os(macOS)
    import Localization
    import SwiftUI

    private enum Metrics {
        static let labelSpacing: CGFloat = .space8
        static let boxHeight: CGFloat = 42
        static let prominentBoxHeight: CGFloat = .size48
        static let boxIconSize: CGFloat = .size16
        static let compactBoxIconSize: CGFloat = 14
        static let copiedHold: Duration = .milliseconds(1500)
        static let optionMinHeight: CGFloat = 46
    }

    public struct MacLabeledField<Content: View>: View {
        let title: String
        var hint: String?
        @ViewBuilder let content: () -> Content

        public init(_ title: String, hint: String? = nil, @ViewBuilder content: @escaping () -> Content) {
            self.title = title
            self.hint = hint
            self.content = content
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: Metrics.labelSpacing) {
                Text(title).type(.caption(.semibold), style: .secondary)
                content()
                if let hint {
                    Text(hint)
                        .type(.caption(.regular), style: .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    public struct MacCopyBox: View {
        let value: String
        var icon: Image?
        var isProminent = false
        var isMonospaced = false
        var copyTitle = L10n.Common.copy
        var copiedTitle = L10n.Common.copied

        public init(
            _ value: String,
            icon: Image? = nil,
            isProminent: Bool = false,
            isMonospaced: Bool = false,
            copyTitle: String = L10n.Common.copy,
            copiedTitle: String = L10n.Common.copied
        ) {
            self.value = value
            self.icon = icon
            self.isProminent = isProminent
            self.isMonospaced = isMonospaced
            self.copyTitle = copyTitle
            self.copiedTitle = copiedTitle
        }

        public var body: some View {
            HStack(spacing: .space8) {
                if let icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: isProminent ? Metrics.boxIconSize : Metrics.compactBoxIconSize,
                            height: isProminent ? Metrics.boxIconSize : Metrics.compactBoxIconSize
                        )
                        .foregroundStyle(Color.secondaryText)
                        .accessibilityHidden(true)
                }
                Text(value)
                    .type(isProminent ? .body1(.regular) : .body2(.regular))
                    .monospaced(isMonospaced)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                MacCopyButton(value, copyTitle: copyTitle, copiedTitle: copiedTitle)
            }
            .padding(.leading, isProminent ? .space16 : .space12)
            .padding(.trailing, .space8)
            .frame(height: isProminent ? Metrics.prominentBoxHeight : Metrics.boxHeight)
            .background(RoundedRectangle(cornerRadius: .radiusControl, style: .continuous).fill(Color.macRow))
        }
    }

    public struct MacCopyButton: View {
        let value: String
        var copyTitle = L10n.Common.copy
        var copiedTitle = L10n.Common.copied

        @State private var isCopied = false

        public init(
            _ value: String,
            copyTitle: String = L10n.Common.copy,
            copiedTitle: String = L10n.Common.copied
        ) {
            self.value = value
            self.copyTitle = copyTitle
            self.copiedTitle = copiedTitle
        }

        public var body: some View {
            Button(isCopied ? copiedTitle : copyTitle) {
                PlatformPasteboard.copy(value)
                withAnimation(DSMotion.controlMorph) { isCopied = true }
            }
            .buttonStyle(.macDS(isCopied ? .success : .primary, size: .small))
            .fixedSize()
            .onChange(of: value) { isCopied = false }
            .task(id: isCopied) {
                guard isCopied, await (try? DSMotion.waitForStep(Metrics.copiedHold)) != nil else { return }
                withAnimation(DSMotion.controlMorph) { isCopied = false }
            }
        }
    }

    public struct MacToggleOption<Detail: View>: View {
        let title: String
        var subtitle: String?
        let isOn: Binding<Bool>
        @ViewBuilder let detail: () -> Detail

        public init(
            _ title: String,
            subtitle: String? = nil,
            isOn: Binding<Bool>,
            @ViewBuilder detail: @escaping () -> Detail
        ) {
            self.title = title
            self.subtitle = subtitle
            self.isOn = isOn
            self.detail = detail
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: .zero) {
                HStack(spacing: .space12) {
                    VStack(alignment: .leading, spacing: .zero) {
                        Text(title).type(.body2(.semibold))
                        if let subtitle {
                            Text(subtitle).type(.caption(.regular), style: .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Toggle(title, isOn: isOn)
                        .labelsHidden()
                        .toggleStyle(.macSwitch)
                }
                .frame(minHeight: Metrics.optionMinHeight)
                if isOn.wrappedValue {
                    detail()
                        .padding(.bottom, .space12)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, .space16)
            .clipped()
            .animation(DSMotion.stateFade, value: isOn.wrappedValue)
        }
    }

    public extension MacToggleOption where Detail == EmptyView {
        init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
            self.init(title, subtitle: subtitle, isOn: isOn) { EmptyView() }
        }
    }

    #Preview("Labeled field") {
        VStack(alignment: .leading, spacing: .space16) {
            MacLabeledField("Label") {
                MacTextField("Label", text: .constant("Website"))
            }
            MacLabeledField("Access Mode", hint: "People can open and download.") {
                MacSegmentedPicker(
                    "Access Mode",
                    options: ["Read Only", "Read & Write"],
                    selection: .constant("Read Only")
                ) { $0 }
            }
        }
        .padding(.space24)
        .previewCanvasWidth(.sheet)
    }

    #Preview("Toggle options") {
        MacFormGroup {
            MacToggleOption("Password protect", isOn: .constant(true)) {
                MacSecureField("Password", text: .constant(""))
            }
            MacToggleOption("Expires", subtitle: "Works until you delete it.", isOn: .constant(false))
        }
        .padding(.space24)
        .previewCanvasWidth(.sheet)
    }

    #Preview("Copy box") {
        VStack(spacing: .space16) {
            MacCopyBox("https://cloud.example.com/share/toks5", icon: IconKit.link, isProminent: true)
            MacCopyBox("https://cloud.example.com/share/k29fa", icon: IconKit.link)
            MacCopyBox("nxt_3f9a0c1e7b2d4a8f9c0e1d2b3a4f5e6d", isMonospaced: true)
        }
        .padding(.space24)
        .previewCanvasWidth(.sheet)
    }
#endif
