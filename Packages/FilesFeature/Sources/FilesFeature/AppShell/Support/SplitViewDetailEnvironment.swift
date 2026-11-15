import SwiftUI

extension EnvironmentValues {
    /// True inside the `MainTabView` split view detail. Read this rather than the size class:
    /// on iPhone Duo open the detail column is narrow enough to report compact.
    @Entry var isSplitViewDetail = false
}
