#if os(macOS)
    import SwiftUI

    public struct MacSwitchToggleStyle: ToggleStyle {
        public init() {}

        public func makeBody(configuration: Configuration) -> some View {
            MacSwitch(configuration: configuration)
        }
    }

    private struct MacSwitch: View {
        let configuration: ToggleStyleConfiguration

        var body: some View {
            Toggle(configuration)
                .toggleStyle(.switch)
                .tint(Color.accent)
                .macDisabledDim()
        }
    }

    public extension ToggleStyle where Self == MacSwitchToggleStyle {
        static var macSwitch: Self {
            MacSwitchToggleStyle()
        }
    }

    #Preview("Switches") {
        VStack(alignment: .leading) {
            Toggle("On", isOn: .constant(true))
            Toggle("Off", isOn: .constant(false))
            Toggle("Disabled", isOn: .constant(false)).disabled(true)
        }
        .toggleStyle(.macSwitch)
        .padding()
    }
#endif
