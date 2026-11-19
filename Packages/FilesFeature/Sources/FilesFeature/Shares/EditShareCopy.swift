import CoreModels
import DesignSystem
import Foundation
import Localization
import SwiftUI

/// Words and glyphs for the edit form, kept out of the reducer so it stays free of copy.
extension EditShareFeature.FieldError {
    var message: String {
        switch self {
        case .pastExpiration: L10n.CreateShare.errorPastExpiration
        case .passwordRequired: L10n.CreateShare.errorPasswordRequired
        }
    }
}

@MainActor
extension EditShareFeature.ExpiryPreset {
    /// The two spans come from the system duration formatter, so every language reads them
    /// natively without strings of their own.
    var title: String {
        switch self {
        case .never: L10n.Common.never
        case .custom: L10n.EditShare.custom
        case .day: Self.spanFormatter.string(from: DateComponents(day: 1)) ?? ""
        case .month: Self.spanFormatter.string(from: DateComponents(month: 1)) ?? ""
        }
    }

    private static let spanFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .month]
        formatter.maximumUnitCount = 1
        return formatter
    }()
}

extension ShareTarget {
    var hint: String {
        switch self {
        case .anyone: L10n.Shared.noAccountNeeded
        case .users: L10n.EditShare.usersHint
        }
    }

    var icon: Image {
        switch self {
        case .anyone: IconKit.web
        case .users: IconKit.people
        }
    }
}

extension ShareAccessMode {
    /// Write access means editing the file itself on a file share, and changing what is inside on
    /// a folder one.
    func hint(isDirectory: Bool) -> String {
        switch self {
        case .readonly: L10n.EditShare.readOnlyHint
        case .readwrite: isDirectory ? L10n.EditShare.readWriteHint : L10n.EditShare.readWriteFileHint
        }
    }

    var icon: Image {
        switch self {
        case .readonly: IconKit.eye
        case .readwrite: IconKit.pencil
        }
    }
}
