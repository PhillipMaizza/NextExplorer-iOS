import Foundation

/// The `activity` object of `GET /api/settings` (admin only): whether the log is being written, and
/// how many days a line is kept. The server accepts 1 to 3650.
public struct ActivitySettings: Equatable, Sendable, Codable {
    public static let retentionRange = 1 ... 3650
    public static let defaultRetentionDays = 90

    public var isEnabled: Bool
    public var retentionDays: Int

    public init(isEnabled: Bool = false, retentionDays: Int = defaultRetentionDays) {
        self.isEnabled = isEnabled
        self.retentionDays = retentionDays
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, retentionDays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        retentionDays = try container.decodeIfPresent(Int.self, forKey: .retentionDays) ?? Self.defaultRetentionDays
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .enabled)
        try container.encode(retentionDays, forKey: .retentionDays)
    }
}

public enum ActivityOutcome: String, CaseIterable, Sendable, Codable {
    case ok
    case refused
}

/// One line of the activity log, from `GET /api/activity`.
public struct ActivityEvent: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    /// The server's ISO 8601 timestamp, kept as sent because it is also the paging cursor.
    public let at: String
    public let action: String
    public let outcome: ActivityOutcome
    public let actor: String?
    public let target: String?
    public let detail: String?
    public let ip: String?

    public init(
        id: String,
        at: String,
        action: String,
        outcome: ActivityOutcome = .ok,
        actor: String? = nil,
        target: String? = nil,
        detail: String? = nil,
        ip: String? = nil
    ) {
        self.id = id
        self.at = at
        self.action = action
        self.outcome = outcome
        self.actor = actor
        self.target = target
        self.detail = detail
        self.ip = ip
    }

    private enum CodingKeys: String, CodingKey {
        case id, at, action, outcome, actor, target, detail, ip
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? container.decode(String.self, forKey: .id) {
            id = text
        } else {
            id = try String(container.decode(Int.self, forKey: .id))
        }
        at = try container.decode(String.self, forKey: .at)
        action = try container.decode(String.self, forKey: .action)
        let rawOutcome = try container.decodeIfPresent(String.self, forKey: .outcome)
        outcome = rawOutcome.flatMap(ActivityOutcome.init(rawValue:)) ?? .ok
        actor = try Self.nonEmpty(container.decodeIfPresent(String.self, forKey: .actor))
        target = try Self.nonEmpty(container.decodeIfPresent(String.self, forKey: .target))
        detail = try Self.nonEmpty(container.decodeIfPresent(String.self, forKey: .detail))
        ip = try Self.nonEmpty(container.decodeIfPresent(String.self, forKey: .ip))
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// The moment as a `Date`, or `nil` when the server sent something unparseable.
    public var date: Date? {
        ServerTimestamp.date(from: at)
    }
}

/// What the activity page filters by. An empty value means "any".
public struct ActivityFilter: Equatable, Sendable {
    public var action: String?
    public var outcome: ActivityOutcome?
    public var query: String

    public init(action: String? = nil, outcome: ActivityOutcome? = nil, query: String = "") {
        self.action = action
        self.outcome = outcome
        self.query = query
    }
}

/// A page of `GET /api/activity`. `nextBefore` is the timestamp to ask from next, `nil` at the end.
public struct ActivityPage: Equatable, Sendable, Decodable {
    public let events: [ActivityEvent]
    public let nextBefore: String?
    public let isEnabled: Bool
    public let actions: [String]

    public init(
        events: [ActivityEvent] = [],
        nextBefore: String? = nil,
        isEnabled: Bool = false,
        actions: [String] = []
    ) {
        self.events = events
        self.nextBefore = nextBefore
        self.isEnabled = isEnabled
        self.actions = actions
    }

    private enum CodingKeys: String, CodingKey {
        case events, nextBefore, enabled, actions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = try container.decodeIfPresent([ActivityEvent].self, forKey: .events) ?? []
        nextBefore = try container.decodeIfPresent(String.self, forKey: .nextBefore)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        actions = try container.decodeIfPresent([String].self, forKey: .actions) ?? []
    }
}
