import Foundation

/// One of the three POSIX permission scopes.
public enum PermissionScope: CaseIterable, Hashable, Sendable {
    case owner
    case group
    case others

    /// Bit offset of this scope's triad within the low 9 bits of a mode.
    var shift: Int {
        switch self {
        case .owner: 6
        case .group: 3
        case .others: 0
        }
    }
}

public enum PermissionRight: CaseIterable, Hashable, Sendable {
    case read
    case write
    case execute

    /// This right's bit within a single octal digit (`r` = 4, `w` = 2, `x` = 1).
    var bit: Int {
        switch self {
        case .read: 4
        case .write: 2
        case .execute: 1
        }
    }
}

/// Response from `GET /api/permissions/*`, confirmed against
/// `backend/src/routes/permissions.js`. `mode` is the raw `stat` integer (file type bits
/// included, e.g. `33188`); the POSIX permission triad is `mode & 0o777`. `owner`/`group`
/// are resolved names where the server could look them up, otherwise the numeric id as a
/// string. This is the only endpoint that exposes ownership at all: `/api/metadata`
/// deliberately omits it.
public struct FilePermissions: Decodable, Equatable, Sendable {
    public let path: String
    public let mode: Int
    public let owner: String
    public let group: String
    public let uid: Int
    public let gid: Int
    public let isDirectory: Bool

    public init(
        path: String,
        mode: Int,
        owner: String,
        group: String,
        uid: Int,
        gid: Int,
        isDirectory: Bool
    ) {
        self.path = path
        self.mode = mode
        self.owner = owner
        self.group = group
        self.uid = uid
        self.gid = gid
        self.isDirectory = isDirectory
    }

    public static func isValidAccountName(_ name: String) -> Bool {
        name.range(of: #"^[a-zA-Z0-9_][a-zA-Z0-9._-]*$"#, options: .regularExpression) != nil
    }

    /// Just the nine permission bits, file type bits masked off.
    public var permissionBits: Int {
        mode & 0o777
    }

    /// Three digit, zero padded octal: the exact shape `POST /api/permissions/chmod`
    /// requires (`/^[0-7]{3}$/`).
    public var octalString: String {
        let raw = String(permissionBits, radix: 8)
        return String(repeating: "0", count: max(0, 3 - raw.count)) + raw
    }

    /// Whether `scope` currently holds `right`.
    public func can(_ scope: PermissionScope, _ right: PermissionRight) -> Bool {
        permissionBits & (right.bit << scope.shift) != 0
    }

    public var grid: [PermissionScope: Set<PermissionRight>] {
        var result: [PermissionScope: Set<PermissionRight>] = [:]
        for scope in PermissionScope.allCases {
            result[scope] = Set(PermissionRight.allCases.filter { can(scope, $0) })
        }
        return result
    }

    /// The three digit octal string a grid of rights maps to, for POSTing back to `chmod`.
    public static func octalString(from grid: [PermissionScope: Set<PermissionRight>]) -> String {
        PermissionScope.allCases.map { scope in
            let digit = (grid[scope] ?? []).reduce(0) { $0 | $1.bit }
            return String(digit)
        }.joined()
    }

    public static func grid(fromOctal text: String) -> [PermissionScope: Set<PermissionRight>]? {
        guard text.count == 3, text.allSatisfy({ ("0" ... "7").contains($0) }), let bits = Int(text, radix: 8) else {
            return nil
        }
        var result: [PermissionScope: Set<PermissionRight>] = [:]
        for scope in PermissionScope.allCases {
            result[scope] = Set(PermissionRight.allCases.filter { bits & ($0.bit << scope.shift) != 0 })
        }
        return result
    }

    public static func symbolicString(from grid: [PermissionScope: Set<PermissionRight>]) -> String {
        let symbols: [PermissionRight: Character] = [.read: "r", .write: "w", .execute: "x"]
        return String(PermissionScope.allCases.flatMap { scope in
            PermissionRight.allCases.map { (grid[scope] ?? []).contains($0) ? symbols[$0] ?? "-" : "-" }
        })
    }
}
