import Foundation

/// The `trash` object of `GET /api/settings` (admin only). Bounds mirror `sanitizeTrash` in the
/// backend's `settingsService.js`.
public struct TrashSettings: Equatable, Sendable, Codable {
    public static let retentionRange = 1 ... 3650
    public static let maxPercentRange = 1 ... 90
    public static let bytesPerGiB = 1024 * 1024 * 1024

    public var isEnabled: Bool
    public var retentionDays: Int
    public var maxPercent: Int
    /// A cap per volume in bytes, `nil` for none. The smaller of the share and the cap applies.
    public var maxBytes: Int?

    public init(isEnabled: Bool = true, retentionDays: Int = 30, maxPercent: Int = 10, maxBytes: Int? = nil) {
        self.isEnabled = isEnabled
        self.retentionDays = retentionDays
        self.maxPercent = maxPercent
        self.maxBytes = maxBytes
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, retentionDays, maxPercent, maxBytes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = TrashSettings()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.isEnabled
        retentionDays = try container.decodeIfPresent(Int.self, forKey: .retentionDays) ?? defaults.retentionDays
        maxPercent = try container.decodeIfPresent(Int.self, forKey: .maxPercent) ?? defaults.maxPercent
        maxBytes = try container.decodeIfPresent(Int.self, forKey: .maxBytes)
    }

    /// `maxBytes` goes out as `null` when there is no cap, which is how the server clears one.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .enabled)
        try container.encode(retentionDays, forKey: .retentionDays)
        try container.encode(maxPercent, forKey: .maxPercent)
        if let maxBytes {
            try container.encode(maxBytes, forKey: .maxBytes)
        } else {
            try container.encodeNil(forKey: .maxBytes)
        }
    }

    /// The cap in GiB as the field shows it: empty for none, at most two decimals.
    public var maxSizeGiBText: String {
        guard let maxBytes, maxBytes > 0 else { return "" }
        let gib = (Double(maxBytes) / Double(Self.bytesPerGiB) * 100).rounded() / 100
        return gib == gib.rounded() ? String(Int(gib)) : String(gib)
    }

    /// Parses the cap field: empty is "no cap" (`.some(nil)`), a positive number is bytes, and
    /// anything else is `nil` (invalid). Accepts a comma as the decimal separator.
    public static func maxBytes(fromGiBText text: String) -> Int?? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if trimmed.isEmpty {
            return .some(nil)
        }
        guard let gib = Double(trimmed), gib.isFinite, gib > 0 else { return nil }
        let bytes = (gib * Double(bytesPerGiB)).rounded()
        guard bytes < Double(Int.max) else { return nil }
        return .some(Int(bytes))
    }
}

/// The `versions` object of `GET /api/settings`. Bounds mirror `VERSION_BOUNDS` in the backend's config.
public struct VersionsSettings: Equatable, Sendable, Codable {
    public static let keepAllHoursRange = 1 ... 720
    public static let hourlyDaysRange = 1 ... 365
    public static let dailyDaysRange = 1 ... 3650
    public static let maxPerFileRange = 1 ... 1000
    public static let sessionCheckpointMinutesRange = 1 ... 1440
    public static let hoursPerDay = 24

    /// The server keeps the tiers in order: hourly versions cannot end before the day of keeping
    /// everything does, so a shorter hourly span is raised to the days that keeping all covers.
    public static func hourlyDays(_ hourlyDays: Int, keepAllHours: Int) -> Int {
        max(hourlyDays, (keepAllHours + hoursPerDay - 1) / hoursPerDay)
    }

    public var isEnabled: Bool
    public var keepAllHours: Int
    public var hourlyDays: Int
    public var dailyDays: Int
    public var maxPerFile: Int
    public var sessionCheckpointMinutes: Int

    public init(
        isEnabled: Bool = true,
        keepAllHours: Int = 24,
        hourlyDays: Int = 7,
        dailyDays: Int = 30,
        maxPerFile: Int = 50,
        sessionCheckpointMinutes: Int = 10
    ) {
        self.isEnabled = isEnabled
        self.keepAllHours = keepAllHours
        self.hourlyDays = hourlyDays
        self.dailyDays = dailyDays
        self.maxPerFile = maxPerFile
        self.sessionCheckpointMinutes = sessionCheckpointMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, keepAllHours, hourlyDays, dailyDays, maxPerFile, sessionCheckpointMinutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = VersionsSettings()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.isEnabled
        keepAllHours = try container.decodeIfPresent(Int.self, forKey: .keepAllHours) ?? defaults.keepAllHours
        hourlyDays = try container.decodeIfPresent(Int.self, forKey: .hourlyDays) ?? defaults.hourlyDays
        dailyDays = try container.decodeIfPresent(Int.self, forKey: .dailyDays) ?? defaults.dailyDays
        maxPerFile = try container.decodeIfPresent(Int.self, forKey: .maxPerFile) ?? defaults.maxPerFile
        sessionCheckpointMinutes = try container
            .decodeIfPresent(Int.self, forKey: .sessionCheckpointMinutes) ?? defaults.sessionCheckpointMinutes
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .enabled)
        try container.encode(keepAllHours, forKey: .keepAllHours)
        try container.encode(hourlyDays, forKey: .hourlyDays)
        try container.encode(dailyDays, forKey: .dailyDays)
        try container.encode(maxPerFile, forKey: .maxPerFile)
        try container.encode(sessionCheckpointMinutes, forKey: .sessionCheckpointMinutes)
    }
}

/// What the last maintenance pass of a volume did, from `GET /api/trash/zones`.
public struct TrashPass: Equatable, Sendable, Decodable {
    public let at: String?
    public let purged: Int
    public let error: String?

    public init(at: String? = nil, purged: Int = 0, error: String? = nil) {
        self.at = at
        self.purged = purged
        self.error = error
    }

    private enum CodingKeys: String, CodingKey {
        case at, purged, error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        at = try container.decodeIfPresent(String.self, forKey: .at)
        purged = try container.decodeIfPresent(Int.self, forKey: .purged) ?? 0
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}

/// One line of a volume's trash journal.
public struct TrashEvent: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    /// The server's name for it, words joined by dashes.
    public let kind: String
    public let itemName: String?
    public let createdAt: String?

    public init(id: String, kind: String, itemName: String? = nil, createdAt: String? = nil) {
        self.id = id
        self.kind = kind
        self.itemName = itemName
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, itemName, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? container.decode(String.self, forKey: .id) {
            id = text
        } else {
            id = try String(container.decode(Int.self, forKey: .id))
        }
        kind = try container.decode(String.self, forKey: .kind)
        itemName = try container.decodeIfPresent(String.self, forKey: .itemName)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

/// A volume's trash and versions space, from `GET /api/trash/zones` (admin only).
public struct TrashZone: Equatable, Sendable, Decodable, Identifiable {
    public enum Kind: String, Sendable {
        case personal
        case volume
        case userVolume = "user-volume"
    }

    public static let fullPercent: Double = 100

    public let id: String
    public let kind: Kind
    public let name: String
    public let isAvailable: Bool
    /// Why it is unavailable: `missing`, `replaced` or `unreadable`.
    public let reason: String?
    public let itemCount: Int
    public let usedBytes: Int
    public let versionCount: Int
    public let versionBytes: Int
    public let budgetBytes: Int?
    public let freeBytes: Int?
    public let lastPass: TrashPass?
    public let events: [TrashEvent]

    public init(
        id: String,
        kind: Kind = .volume,
        name: String,
        isAvailable: Bool = true,
        reason: String? = nil,
        itemCount: Int = 0,
        usedBytes: Int = 0,
        versionCount: Int = 0,
        versionBytes: Int = 0,
        budgetBytes: Int? = nil,
        freeBytes: Int? = nil,
        lastPass: TrashPass? = nil,
        events: [TrashEvent] = []
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.isAvailable = isAvailable
        self.reason = reason
        self.itemCount = itemCount
        self.usedBytes = usedBytes
        self.versionCount = versionCount
        self.versionBytes = versionBytes
        self.budgetBytes = budgetBytes
        self.freeBytes = freeBytes
        self.lastPass = lastPass
        self.events = events
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, name, available, reason, itemCount, usedBytes, versionCount, versionBytes, budgetBytes,
             freeBytes,
             lastPass, events
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let rawKind = try container.decodeIfPresent(String.self, forKey: .kind)
        kind = rawKind.flatMap(Kind.init(rawValue:)) ?? .volume
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        isAvailable = try container.decodeIfPresent(Bool.self, forKey: .available) ?? true
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        itemCount = try container.decodeIfPresent(Int.self, forKey: .itemCount) ?? 0
        usedBytes = try container.decodeIfPresent(Int.self, forKey: .usedBytes) ?? 0
        versionCount = try container.decodeIfPresent(Int.self, forKey: .versionCount) ?? 0
        versionBytes = try container.decodeIfPresent(Int.self, forKey: .versionBytes) ?? 0
        budgetBytes = try container.decodeIfPresent(Int.self, forKey: .budgetBytes)
        freeBytes = try container.decodeIfPresent(Int.self, forKey: .freeBytes)
        lastPass = try container.decodeIfPresent(TrashPass.self, forKey: .lastPass)
        events = try container.decodeIfPresent([TrashEvent].self, forKey: .events) ?? []
    }

    /// What the volume holds, the trash and the versions together, since they share its budget.
    public var heldBytes: Int {
        usedBytes + versionBytes
    }

    /// The share of the budget held, 0 to 1, or 0 when there is no limit.
    public var usedFraction: Double {
        guard let budgetBytes, budgetBytes > 0 else { return 0 }
        return min(1, Double(heldBytes) / Double(budgetBytes))
    }

    /// The share of the budget held, 0 to 100, or 0 when there is no limit.
    public var usedPercent: Int {
        guard let budgetBytes, budgetBytes > 0 else { return 0 }
        return Int(min(Self.fullPercent, (Double(heldBytes) / Double(budgetBytes) * Self.fullPercent).rounded()))
    }
}

/// The answer to `POST /api/trash/verify` for one volume: how many invariants it broke.
public struct TrashVerification: Equatable, Sendable, Decodable {
    /// One invariant a volume broke, as the server names it.
    public struct Violation: Equatable, Sendable, Decodable {
        public let invariant: String
        public let detail: String

        public init(invariant: String, detail: String) {
            self.invariant = invariant
            self.detail = detail
        }

        private enum CodingKeys: String, CodingKey {
            case invariant, detail
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            invariant = try container.decodeIfPresent(String.self, forKey: .invariant) ?? ""
            detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        }
    }

    /// A violation of a shape this app does not know still counts, with nothing to say about it.
    private struct Lenient: Decodable {
        let violation: Violation

        init(from decoder: Decoder) throws {
            violation = (try? Violation(from: decoder)) ?? Violation(invariant: "", detail: "")
        }
    }

    public let zoneID: String
    public let violations: [Violation]

    public var violationCount: Int {
        violations.count
    }

    public init(zoneID: String, violations: [Violation] = []) {
        self.zoneID = zoneID
        self.violations = violations
    }

    private enum CodingKeys: String, CodingKey {
        case zoneId, violations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zoneID = try container.decode(String.self, forKey: .zoneId)
        violations = try (container.decodeIfPresent([Lenient].self, forKey: .violations) ?? []).map(\.violation)
    }
}
