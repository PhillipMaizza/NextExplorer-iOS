public extension User {
    static let preview = User(
        id: "preview-user",
        username: "jdoe",
        email: "jane.doe@example.com",
        displayName: "Jane Doe"
    )

    static let previewAdmin = User(
        id: preview.id,
        username: preview.username,
        email: preview.email,
        displayName: preview.displayName,
        roles: [UserRole.admin]
    )
}
