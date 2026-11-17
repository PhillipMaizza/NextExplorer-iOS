import CoreModels
@testable import FilesFeature
import Testing

struct UserDisplayLabelTests {
    private func user(displayName: String?) -> User {
        User(id: "u1", username: "jdoe", email: "jane@example.com", displayName: displayName)
    }

    @Test
    func aMissingDisplayNameFallsBackToTheUsername() {
        #expect(user(displayName: nil).displayLabel == "jdoe")
    }

    @Test(arguments: ["", " ", "\n\t "])
    func aBlankDisplayNameFallsBackToTheUsernameInsteadOfRenderingNothing(blank: String) {
        #expect(user(displayName: blank).displayLabel == "jdoe")
    }

    @Test
    func aRealDisplayNameWins() {
        #expect(user(displayName: "Jane Doe").displayLabel == "Jane Doe")
    }
}
