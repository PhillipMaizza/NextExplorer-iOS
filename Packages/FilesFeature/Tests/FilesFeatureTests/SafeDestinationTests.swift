import Foundation
import Testing

@testable import FilesFeature

/// `SafeDestination.within` is the guard that stops a crafted archive entry name or HTML
/// `src`/`href` value (both attacker-influenced) from writing outside its sandbox folder.
@Suite
struct SafeDestinationTests {
    private let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("SafeDestinationTests", isDirectory: true)

    @Test("a plain relative name resolves inside the base directory")
    func plainNameStaysInside() throws {
        let resolved = try #require(SafeDestination.within(base, "style.css"))
        #expect(resolved.path == base.standardizedFileURL.appendingPathComponent("style.css").path)
    }

    @Test("a nested relative path resolves inside the base directory")
    func nestedPathStaysInside() throws {
        let resolved = try #require(SafeDestination.within(base, "assets/js/app.js"))
        #expect(resolved.path.hasPrefix(base.standardizedFileURL.path + "/"))
    }

    @Test("a parent-directory traversal is rejected")
    func parentTraversalRejected() {
        #expect(SafeDestination.within(base, "../escape.txt") == nil)
        #expect(SafeDestination.within(base, "a/../../escape.txt") == nil)
        #expect(SafeDestination.within(base, "../../../../etc/passwd") == nil)
    }

    @Test("a traversal that lands back inside after normalising is allowed")
    func traversalNettingBackInsideIsAllowed() throws {
        let resolved = try #require(SafeDestination.within(base, "a/b/../c.txt"))
        #expect(resolved.lastPathComponent == "c.txt")
        #expect(resolved.path.hasPrefix(base.standardizedFileURL.path + "/"))
    }

    @Test("the base directory itself is accepted, an empty component is not a traversal")
    func baseItselfIsAllowed() throws {
        let resolved = try #require(SafeDestination.within(base, ""))
        #expect(resolved.path == base.standardizedFileURL.path)
    }
}
