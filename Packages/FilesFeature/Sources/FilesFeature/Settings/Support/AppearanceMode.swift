import Localization
import SwiftUI

/// The app's color scheme preference. Persisted as the two existing keys
/// (`AppStorageKeys.appearanceOverrideSet` + `prefersDarkMode`) so installs that already picked
/// light or dark keep their choice; `system` is simply "no override".
public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String {
        rawValue
    }

    public init(hasOverride: Bool, prefersDark: Bool) {
        if hasOverride {
            self = prefersDark ? .dark : .light
        } else {
            self = .system
        }
    }

    public var title: String {
        switch self {
        case .system: L10n.Appearance.system
        case .light: L10n.Appearance.light
        case .dark: L10n.Appearance.dark
        }
    }

    public var hasOverride: Bool {
        self != .system
    }

    public var prefersDark: Bool {
        self == .dark
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
