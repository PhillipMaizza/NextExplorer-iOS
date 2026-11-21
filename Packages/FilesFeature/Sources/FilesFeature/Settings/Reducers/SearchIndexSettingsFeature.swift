import CoreModels
import Foundation

/// An admin switching the server's search index on or off and curating the folders it leaves
/// alone. Mirrors the web client's `SettingsSearchIndex.vue`. The server's `SEARCH_INDEX`
/// variable can decide the switch.
public typealias SearchIndexSettingsFeature = ExcludedPathsSettingsFeature<SearchIndexSection>

public enum SearchIndexSection: ExcludedPathsSection {
    public static let defaultChoice = false
    public static let missingMessage = "Settings response carried no search index."

    public static func section(of settings: SystemSettings) -> SearchIndexSettings? {
        settings.searchIndex
    }

    public static func choice(of settings: SearchIndexSettings) -> Bool {
        settings.isEnabled
    }

    public static func excluded(of settings: SearchIndexSettings) -> ExcludedPaths {
        settings.excluded
    }

    public static func lockedBy(_ features: ServerFeatures) -> String? {
        features.searchIndexLockedBy
    }

    public static func effectiveChoice(_ features: ServerFeatures) -> Bool {
        features.isSearchIndexEnabled
    }

    public static func patch(choice: Bool) -> SystemSettingsPatch {
        SystemSettingsPatch(searchIndex: .init(isEnabled: choice))
    }

    public static func patch(excludedPaths: [String]) -> SystemSettingsPatch {
        SystemSettingsPatch(searchIndex: .init(excludedPaths: excludedPaths))
    }
}

extension SearchIndexSettingsFeature.State {
    var isEnabled: Bool {
        choice
    }
}
