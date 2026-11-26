#if os(macOS)
    import CoreModels
    import DesignSystem
    import SwiftUI

    enum MacInspectorLocation {
        static func parent(of item: FileItem) -> String {
            (item.id as NSString).deletingLastPathComponent
        }

        static func title(parent: String) -> String {
            PersonalSpace.folderTitle(parent)
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
