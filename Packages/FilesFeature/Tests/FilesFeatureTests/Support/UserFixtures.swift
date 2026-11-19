import CoreModels
import TestUtils

extension User {
    /// The signed in account of the settings, shell and share tests.
    static let jdoeFixture = User(id: "1", username: TestUser.jdoe, email: nil)
    /// The same account with the profile details the settings pages show.
    static let janeDoeFixture = User(
        id: "1",
        username: TestUser.jdoe,
        email: "jane.doe@example.com",
        displayName: "Jane Doe"
    )
    /// The one other account the share tests offer as someone to share with.
    static let jamieFixture = User(id: "u2", username: "jamie", email: "jamie@example.com", displayName: "Jamie")
}
