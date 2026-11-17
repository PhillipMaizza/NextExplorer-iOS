@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("UserVolume decoding")
struct UserVolumeTests {
    @Test("decodes a volume with its access mode and an absent updatedAt")
    func decodesVolume() throws {
        let volume = try CoreModelsFixture.userVolumeVolume.decodeISO(UserVolume.self)
        #expect(volume == UserVolume(
            id: "uv1",
            userId: "u1",
            label: "Archive",
            path: "/mnt/archive",
            accessMode: .readonly,
            createdAt: MockDate.date,
            updatedAt: nil
        ))
    }

    @Test("an admin directory listing at the root has no parent and one entry per directory")
    func decodesListingAtRoot() throws {
        let listing = try CoreModelsFixture.userVolumeDirectoryListingAtRoot.decode(AdminDirectoryListing.self)
        #expect(listing.current == "/mnt")
        #expect(listing.parent == nil)
        #expect(listing.directories == [
            AdminDirectory(name: "archive", path: "/mnt/archive"),
            AdminDirectory(name: "media", path: "/mnt/media"),
        ])
    }
}
