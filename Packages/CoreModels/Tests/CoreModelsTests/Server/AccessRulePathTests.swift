@testable import CoreModels
import Testing

struct AccessRulePathTests {
    @Test(arguments: [
        ("Files/Photos", "Files/Photos"),
        ("/Files/Photos", "Files/Photos"),
        ("/../Files/zz", "Files/zz"),
        ("Files//a/./b/", "Files/a/b/"),
        ("Files\\a", "Files/a"),
        ("./", "./"),
        ("Files/ zz ", "Files/ zz "),
        ("/", ""),
        (".", ""),
        ("//", ""),
    ] as [(String, String?)])
    func normalizesLikeTheServer(raw: String, expected: String?) {
        #expect(AccessRule.normalizedRelativePath(raw) == expected)
    }

    @Test(arguments: ["..", "../x", "a/../..", "a/../../b"])
    func refusesATraversal(raw: String) {
        #expect(AccessRule.normalizedRelativePath(raw) == nil)
    }

    @Test(arguments: [
        ("Files/Photos", true),
        (" zz ", true),
        ("./", true),
        ("/", false),
        ("..", false),
        ("   ", false),
    ])
    func acceptsWhatTheServerSaves(path: String, isAccepted: Bool) {
        #expect(AccessRule(id: "a", path: path, isRecursive: true, permission: .readOnly).isPathAccepted == isAccepted)
    }
}
