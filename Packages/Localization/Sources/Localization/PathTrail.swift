public enum PathTrail {
    public static func text(_ location: String) -> String {
        let parts = location.split(separator: "/").map(String.init)
        return parts.dropFirst().reduce(parts.first ?? location) { L10n.Shared.pathStep($0, $1) }
    }
}
