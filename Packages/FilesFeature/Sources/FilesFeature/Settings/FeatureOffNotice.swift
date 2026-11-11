import DesignSystem
import Localization
import SwiftUI

/// Said on a settings page for a feature that is switched off. The page stays reachable, because
/// preparing a list before turning something on is reasonable, but a form that governs nothing
/// says so and names the variable to set. A page with a switch of its own points at the switch.
struct FeatureOffNotice: View {
    let setting: String
    let isSwitchable: Bool

    var body: some View {
        DSInfoCard(
            [
                L10n.ServerSettings.featureOffTitle,
                isSwitchable ? L10n.ServerSettings.featureOffUseSwitch : L10n.ServerSettings.featureOffHowTo(setting),
                L10n.ServerSettings.featureOffKept,
            ].joined(separator: "\n")
        )
    }
}

#Preview("Switch on this page") {
    FeatureOffNotice(setting: "SEARCH_INDEX=true", isSwitchable: true)
        .padding()
}

#Preview("Set in the environment") {
    FeatureOffNotice(setting: "FOLDER_SIZE_MODE=full", isSwitchable: false)
        .padding()
}
