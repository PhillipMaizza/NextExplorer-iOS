import DesignSystem
import Localization
import SwiftUI

/// How the per item download action reads. A Mac saves into a folder of the user's choice and says
/// Download; an iPhone or iPad copies the file out of the app and says Save to Device, files only.
enum SaveActionStyle {
    static var title: String {
        #if os(macOS)
            L10n.Browse.actionDownload
        #else
            L10n.Browse.actionSaveToDevice
        #endif
    }

    static var icon: Image {
        IconKit.download
    }

    static func isAvailable(for isDirectory: Bool) -> Bool {
        #if os(macOS)
            true
        #else
            !isDirectory
        #endif
    }
}
