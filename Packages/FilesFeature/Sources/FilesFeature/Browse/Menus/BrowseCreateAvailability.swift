import SwiftUI

public struct BrowseCreateAvailability: Equatable, Sendable {
    public let canCreateFolder: Bool
    public let canCreateFile: Bool
}

public extension FocusedValues {
    @Entry var browseCreateAvailability: BrowseCreateAvailability?
}

extension BrowseFeature.State {
    var createAvailability: BrowseCreateAvailability {
        BrowseCreateAvailability(
            canCreateFolder: !directoryPath.isEmpty && canCreateFolderHere,
            canCreateFile: !directoryPath.isEmpty && canCreateFileHere
        )
    }
}
