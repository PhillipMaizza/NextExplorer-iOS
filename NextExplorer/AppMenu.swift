import AppFeature
import ComposableArchitecture
import FilesFeature
import Localization
import SwiftUI

/// What the Mac menu bar and the iPad keyboard commands share: the sections ⌘1, ⌘2… switch to,
/// and the way a command reaches the signed in session.
enum AppMenu {
    typealias Section = (tab: MainTabFeature.Tab, title: String, key: KeyEquivalent)

    /// Computed, not stored: the titles must follow a language change. The Mac lists Offline in
    /// its sidebar only.
    static func sections(includingOffline: Bool) -> [Section] {
        var sections: [Section] = [
            (.browse, L10n.Tab.browse, "1"),
            (.favorites, L10n.Tab.favorites, "2"),
            (.shared, L10n.Tab.shared, "3"),
        ]
        if includingOffline {
            sections.append((.downloads, L10n.Tab.offline, "4"))
        }
        return sections
    }

    /// Menu items stay visible while signed out; they simply do nothing until a session exists.
    @MainActor
    static func send(_ action: MainTabFeature.Action, to store: StoreOf<AppFeature>) {
        guard case .authenticated = store.destination else { return }
        store.send(.destination(.authenticated(.mainTab(action))))
    }
}
