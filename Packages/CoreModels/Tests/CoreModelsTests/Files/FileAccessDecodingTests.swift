@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("FileAccess decoding")
struct FileAccessDecodingTests {
    @Test("happy path: decodes a full read/write grant")
    func decodesFullGrant() throws {
        let access = try CoreModelsFixture.fileAccessFullGrant.decode(FileAccess.self)
        #expect(access.canRead == true)
        #expect(access.canDelete == true)
    }

    @Test("edge case: a read-only grant reports every write-capable flag as false")
    func decodesReadOnlyGrant() throws {
        let access = try CoreModelsFixture.fileAccessReadOnlyGrant.decode(FileAccess.self)
        #expect(access.canWrite == false)
        #expect(access.canUpload == false)
        #expect(access.canDelete == false)
        #expect(access.canShare == false)
        #expect(access.canDownload == true)
    }

    @Test("error path: missing required field fails to decode")
    func missingRequiredFieldThrows() throws {
        let data = try CoreModelsFixture.fileAccessMissingRequiredFields.data()
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(FileAccess.self, from: data)
        }
    }

    @Test("Creating files and folders is answered apart from uploading")
    func decodesCreatePermissions() throws {
        let access = try CoreModelsFixture.fileAccessWithCreateFlags.decode(FileAccess.self)
        #expect(access.canUpload)
        #expect(access.canCreateFolder)
        #expect(!access.canCreateFile)
    }

    @Test("A server or saved listing without the create flags falls back to the upload flag")
    func createPermissionsFallBackToUpload() throws {
        let access = try CoreModelsFixture.fileAccessWithoutCreateFlags.decode(FileAccess.self)
        #expect(!access.canCreateFile)
        #expect(!access.canCreateFolder)
    }

    @Test("A listing saved for offline use keeps the create flags")
    func roundTrips() throws {
        let access = FileAccess(
            canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true,
            canCreateFolder: false, canCreateFile: true
        )
        let decoded = try JSONDecoder().decode(FileAccess.self, from: JSONEncoder().encode(access))
        #expect(decoded == access)
    }
}
