import SwiftUI

private enum Constants {
    static let iconSize: CGFloat = .iconSmall
}

/// A labeled `Toggle` with a leading icon, the shape every settings-style switch row in
/// the app shares (dark mode, show hidden files, show thumbnails, ...).
public struct DSToggleRow: View {
    private let title: String
    private let icon: Image
    @Binding private var isOn: Bool

    public init(title: String, icon: Image, isOn: Binding<Bool>) {
        self.title = title
        self.icon = icon
        self._isOn = isOn
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                Text(title).type(.body2(.regular), style: .primary(for: .label))
            } icon: {
                icon
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.primaryDS)
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
            }
        }
        .tint(Color.accent)
        .hapticFeedback(.selection, trigger: isOn)
    }
}

#Preview {
    VStack(spacing: .space16) {
        DSToggleRow(title: "Dark Mode", icon: IconKit.moonFill, isOn: .constant(true))
        DSToggleRow(title: "Show Hidden Files", icon: IconKit.eye, isOn: .constant(false))
        DSToggleRow(title: "Show Thumbnails", icon: IconKit.photo, isOn: .constant(true))
    }
    .padding(.space16)
    .background(Color.backgroundPrimary)
}
