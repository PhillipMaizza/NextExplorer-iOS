#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    enum MacInspectorLocation {
        static func parent(of item: FileItem) -> String {
            (item.id as NSString).deletingLastPathComponent
        }

        static func title(parent: String) -> String {
            PersonalSpace.folderTitle(parent)
        }

        static func folderTitle(of item: FileItem, on screen: BrowseFeature.State) -> String? {
            let parent = parent(of: item)
            if !parent.isEmpty, parent == screen.directoryPath {
                return screen.title
            }
            if let shareName = screen.shareName, !parent.isEmpty, ReceivedShareSpace.shareRoot(of: parent) == parent {
                return shareName
            }
            return ReceivedShareSpace.shareRoot(of: item.id) == item.id ? L10n.Shared.sharedWithMe : nil
        }

        static func trail(parent: String) -> String {
            parent.isEmpty ? PersonalSpace.folderTitle(parent) : PersonalSpace.trail(parent)
        }
    }

    public struct MacInspectorAction {
        let perform: () -> Void

        public func callAsFunction() {
            perform()
        }
    }

    public extension FocusedValues {
        @Entry var closeMacInspector: MacInspectorAction?
        @Entry var openMacInspector: MacInspectorAction?
    }
#endif
