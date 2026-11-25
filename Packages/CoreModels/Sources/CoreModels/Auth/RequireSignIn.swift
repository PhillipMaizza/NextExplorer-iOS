import Foundation

public struct RequireSignIn: Codable, Equatable, Sendable {
    public var lockAfter: LockAfter
    public var shouldKeepOfflineFiles: Bool

    public init(lockAfter: LockAfter = .oneMinute, shouldKeepOfflineFiles: Bool = true) {
        self.lockAfter = lockAfter
        self.shouldKeepOfflineFiles = shouldKeepOfflineFiles
    }

    public enum LockAfter: String, Codable, CaseIterable, Sendable {
        case appStart
        case immediately
        case thirtySeconds
        case oneMinute
        case fiveMinutes

        public var timeAway: Duration? {
            switch self {
            case .appStart: nil
            case .immediately: .zero
            case .thirtySeconds: .seconds(30)
            case .oneMinute: .seconds(60)
            case .fiveMinutes: .seconds(300)
            }
        }

        public func locks(after away: Duration) -> Bool {
            guard let timeAway else { return false }
            return away >= timeAway
        }
    }
}
