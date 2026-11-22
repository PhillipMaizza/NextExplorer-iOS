#if os(macOS)
    import SwiftUI

    public struct MacSwitchToggleStyle: ToggleStyle {
        public init() {}

        public func makeBody(configuration: Configuration) -> some View {
            Toggle(configuration)
                .toggleStyle(.switch)
                .tint(Color.accent)
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
        }
        .toggleStyle(.macSwitch)
        .padding()
    }
#endif
