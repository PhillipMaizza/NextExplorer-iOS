public struct PathCrumb: Equatable, Sendable {
    public let title: String
    public let path: String

    public init(title: String, path: String) {
        self.title = title
        self.path = path
    }
}
