import Localization

public struct PathCrumb: Equatable, Sendable {
    public let title: String
    public let path: String

    public init(title: String, path: String) {
        self.title = title
        self.path = path
    }

    public static func trail(for directoryPath: String, title: String = "", shareName: String? = nil) -> [PathCrumb] {
        let segments = directoryPath.split(separator: "/").map(String.init)
        if let root = PersonalSpace.receivedShareRoot(of: directoryPath) {
            let name = shareName ?? (directoryPath == root && !title.isEmpty ? title : segments[1])
            let inner = Array(segments.dropFirst(2))
            return [
                PathCrumb(title: L10n.Shared.sharedWithMe, path: PersonalSpace.receivedSharesRootPath),
                PathCrumb(title: name, path: root),
            ] + inner.indices.map { PathCrumb(title: inner[$0], path: ([root] + inner[...$0]).joined(separator: "/")) }
        }
        return segments.indices.map { index in
            PathCrumb(
                title: PersonalSpace.displayName(forSegment: segments[index], isFirstSegment: index == 0),
                path: segments[...index].joined(separator: "/")
            )
        }
    }
}
