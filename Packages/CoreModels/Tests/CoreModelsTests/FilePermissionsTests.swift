import Foundation
import Testing

@testable import CoreModels

@Suite
struct FilePermissionsTests {
    @Test
    func decodesTheBackendShape() throws {
        let json = """
        {
            "path": "Documents/report.pdf",
            "mode": 33261,
            "owner": "phillip",
            "group": "staff",
            "uid": 501,
            "gid": 20,
            "isDirectory": false
        }
        """.data(using: .utf8)!

        let perms = try JSONDecoder().decode(FilePermissions.self, from: json)
        #expect(perms.mode == 33261)
        #expect(perms.owner == "phillip")
        #expect(!perms.isDirectory)
    }

    @Test
    func permissionBitsMasksOffTheFileTypeBits() {
        // 33261 = 0o100755 (regular file, rwxr-xr-x)
        let perms = make(mode: 33261)
        #expect(perms.permissionBits == 0o755)
        #expect(perms.octalString == "755")
    }

    @Test
    func octalStringZeroPadsToThreeDigits() {
        #expect(make(mode: 0o004).octalString == "004")
        #expect(make(mode: 0o000).octalString == "000")
        #expect(make(mode: 0o040).octalString == "040")
    }

    @Test
    func canReportsEachRightPerScope() {
        let perms = make(mode: 0o754) // rwx r-x r--
        #expect(perms.can(.owner, .read) && perms.can(.owner, .write) && perms.can(.owner, .execute))
        #expect(perms.can(.group, .read) && !perms.can(.group, .write) && perms.can(.group, .execute))
        #expect(perms.can(.others, .read) && !perms.can(.others, .write) && !perms.can(.others, .execute))
    }

    @Test
    func gridRoundTripsThroughOctalString() {
        let perms = make(mode: 0o640)
        let grid = perms.grid
        #expect(grid[.owner] == [.read, .write])
        #expect(grid[.group] == [.read])
        #expect(grid[.others] == [])
        #expect(FilePermissions.octalString(from: grid) == "640")
    }

    private func make(mode: Int) -> FilePermissions {
        FilePermissions(path: "x", mode: mode, owner: "u", group: "g", uid: 0, gid: 0, isDirectory: false)
    }
}
