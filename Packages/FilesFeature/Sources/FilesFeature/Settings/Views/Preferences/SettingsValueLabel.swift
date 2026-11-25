import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let iconSize: CGFloat = .iconSmall
}

struct SettingsValueLabel: View {
    let title: String
    let value: String
    let icon: Image

    var body: some View {
        Label {
            HStack {
                Text(title).type(.body2(.regular), style: .primaryOnSurface)
                Spacer()
                Text(value).type(.body2(.regular), style: .secondary)
            }
        } icon: {
            icon
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .frame(width: Constants.iconSize, height: Constants.iconSize)
        }
    }
}

#Preview {
    List {
        SettingsValueLabel(title: L10n.Settings.rowDefaultSort, value: L10n.Sort.name, icon: IconKit.sort)
    }
}
