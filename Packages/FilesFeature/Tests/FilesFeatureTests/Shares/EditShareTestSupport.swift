import CoreModels
import Foundation
import TestUtils

extension Share {
    /// The By me folder share the edit tests work on.
    static func editFixture(
        label: String? = "Report",
        accessMode: ShareAccessMode = .readonly,
        target: ShareTarget = .anyone,
        hasPassword: Bool = false,
        expiresAt: Date? = nil,
        permittedUserIds: [String]? = nil
    ) -> Share {
        Share(
            id: "s1", shareToken: "AbC123xyz0", ownerId: "u1",
            sourcePath: "Docs/Report", isDirectory: true,
            accessMode: accessMode, sharingType: target, hasPassword: hasPassword,
            expiresAt: expiresAt, label: label, downloadCount: 2, lastAccessedAt: nil,
            permittedUserIds: permittedUserIds,
            createdAt: MockDate.date,
            updatedAt: MockDate.date
        )
    }
}
