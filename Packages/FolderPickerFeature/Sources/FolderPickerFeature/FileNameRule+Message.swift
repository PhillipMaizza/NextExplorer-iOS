import CoreModels
import Localization

/// The reasons a typed name is refused, worded for the user: shared by every screen that takes a name
/// (rename, new folder, the share sheet's file names).
public extension FileNameRule.Problem {
    var message: String {
        switch self {
        case .reserved: L10n.Browse.nameErrorReserved
        case .separators: L10n.Browse.nameErrorSeparators
        }
    }
}
