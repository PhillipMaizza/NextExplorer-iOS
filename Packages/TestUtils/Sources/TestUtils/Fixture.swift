import Foundation

/// A test target's fixture files, named by an enum so a typo is a compile error and an audit test can
/// prove every case has a file on disk and every file has a case.
///
/// ```swift
/// enum CoreModelsFixture: String, FixtureFile {
///     static let bundle = Bundle.module         // the one place a target names its bundle
///     case userAdmin = "user/admin"            // Fixtures/user/admin.json
///     case userTruncated = "user/truncated"    // invalid JSON on purpose
/// }
/// let user = try CoreModelsFixture.userAdmin.decode(User.self)
/// let data = try CoreModelsFixture.userTruncated.data()
/// ```
///
/// The test target declares `resources: [.copy("Fixtures")]` and has one audit test calling `audit()`.
public protocol FixtureFile: RawRepresentable, CaseIterable, Sendable where RawValue == String {
    /// The test target's resource bundle: `Bundle.module` declared in the enum.
    static var bundle: Bundle { get }

    /// File extension of this fixture, `json` unless a case says otherwise.
    var fileExtension: String { get }
}

public enum Fixture {
    public struct Missing: Error, CustomStringConvertible {
        let path: String
        public var description: String {
            "Missing test fixture Fixtures/\(path)"
        }
    }
}

public extension FixtureFile {
    var fileExtension: String {
        "json"
    }

    func data() throws -> Data {
        let path = rawValue as NSString
        let directory = path.deletingLastPathComponent
        let subdirectory = directory.isEmpty ? "Fixtures" : "Fixtures/\(directory)"
        guard let file = Self.bundle.url(
            forResource: path.lastPathComponent,
            withExtension: fileExtension,
            subdirectory: subdirectory
        ) else {
            throw Fixture.Missing(path: "\(rawValue).\(fileExtension)")
        }
        return try Data(contentsOf: file)
    }

    func string() throws -> String {
        try String(decoding: data(), as: UTF8.self)
    }

    func decode<Value: Decodable>(
        _ type: Value.Type = Value.self,
        using decoder: JSONDecoder = JSONDecoder()
    ) throws -> Value {
        try decoder.decode(type, from: data())
    }

    /// Cases whose file is missing, and files in `Fixtures` that no case names. Both must be empty.
    static func audit() -> (missing: [String], orphans: [String]) {
        let missing = allCases.compactMap { file -> String? in
            (try? file.data()) == nil ? "\(file.rawValue).\(file.fileExtension)" : nil
        }
        let named = Set(allCases.map { "\($0.rawValue).\($0.fileExtension)" })
        var onDisk: [String] = []
        if let root = bundle.resourceURL?.appendingPathComponent("Fixtures"),
           let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        {
            for case let url as URL in walker
                where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            {
                onDisk.append(String(url.path.dropFirst(root.path.count + 1)))
            }
        }
        return (missing.sorted(), onDisk.filter { !named.contains($0) }.sorted())
    }
}
