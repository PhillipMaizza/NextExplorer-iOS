import CoreModels
import Foundation

/// An admin choosing how far folder sizes are counted (`off`, `shallow`, `full`) and which
/// folders to skip. Mirrors the web client's `SettingsFolderSize.vue`. The server's
/// `FOLDER_SIZE_MODE` variable can decide the mode.
public typealias FolderSizeSettingsFeature = ExcludedPathsSettingsFeature<FolderSizeSection>

public enum FolderSizeSection: ExcludedPathsSection {
    public static let defaultChoice = FolderSizeMode.off
    public static let missingMessage = "Settings response carried no folder size."

    public static func section(of settings: SystemSettings) -> FolderSizeSettings? {
        settings.folderSize
    }

    public static func choice(of settings: FolderSizeSettings) -> FolderSizeMode {
        settings.mode
    }

    public static func excluded(of settings: FolderSizeSettings) -> ExcludedPaths {
        settings.excluded
    }

    public static func lockedBy(_ features: ServerFeatures) -> String? {
        features.folderSizeLockedBy
    }

    public static func effectiveChoice(_ features: ServerFeatures) -> FolderSizeMode {
        features.folderSizeMode
    }

    public static func patch(choice: FolderSizeMode) -> SystemSettingsPatch {
        SystemSettingsPatch(folderSize: .init(mode: choice))
    }

    public static func patch(excludedPaths: [String]) -> SystemSettingsPatch {
        SystemSettingsPatch(folderSize: .init(excludedPaths: excludedPaths))
    }
}

extension FolderSizeSettingsFeature.State {
    var mode: FolderSizeMode {
        choice
    }
}
