#if os(macOS) && DEBUG
    import CoreModels
    import Foundation

    extension SettingsFeature.State {
        /// A signed in admin, for the Mac Settings tab previews.
        static var macPreview: Self {
            Self(
                serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
                user: User(id: "preview-user", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe", roles: [UserRole.admin])
            )
        }
    }
#endif
