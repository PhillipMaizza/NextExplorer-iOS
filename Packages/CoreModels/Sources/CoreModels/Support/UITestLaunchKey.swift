/// The launch environment keys the UI tests set and the mocked app reads, named once for both.
public enum UITestLaunchKey: String, CaseIterable, Sendable {
    case mock = "UITEST_MOCK"
    case auth = "UITEST_AUTH"
    case scenario = "UITEST_SCENARIO"
    case animationSpeed = "UITEST_ANIM_SPEED"
    case disableAnimations = "UITEST_DISABLE_ANIMATIONS"
    case orientation = "UITEST_ORIENTATION"
    /// Seeds one file saved by an earlier version into the Offline tab's "Saved earlier" list.
    case legacyDownloads = "UITEST_LEGACY_DOWNLOADS"
    case searchOffline = "UITEST_SEARCH_OFFLINE"
    case offlineLaunch = "UITEST_OFFLINE_LAUNCH"
    /// A comma list of `UITestArea`s whose routes fail, as a server error would.
    case failingAreas = "UITEST_FAIL"
    /// A comma list of `UITestArea`s whose routes answer with nothing in them.
    case emptyAreas = "UITEST_EMPTY"

    /// The value that switches a flag key on.
    public static let on = "1"
    /// The `orientation` value that rotates the window.
    public static let landscape = "landscape"
}

/// A part of the mocked server a UI test can make fail or come back empty on its own, so one test
/// reaches an error or empty state without changing the rest of the world.
public enum UITestArea: String, CaseIterable, Sendable {
    case browse
    case search
    case favorites
    case shares
    case trash
    case users
    case activity
    case versions
    case accessRules
    case apiTokens

    private static let separator: Character = ","

    /// The areas a launch value names; unknown names are skipped.
    public static func parse(_ value: String?) -> Set<UITestArea> {
        Set((value ?? "").split(separator: separator).compactMap { UITestArea(rawValue: String($0)) })
    }

    /// The launch value naming `areas`.
    public static func launchValue(_ areas: Set<UITestArea>) -> String {
        areas.map(\.rawValue).sorted().joined(separator: String(separator))
    }
}
