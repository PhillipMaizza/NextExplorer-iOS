import CoreModels
import Foundation

private enum Constants {
    static let secondsPerDay: TimeInterval = 86_400
    /// A link expiring within this many days shows its countdown on the row.
    static let expiryWarningDays = 7
    /// Below this many entries besides All the people row would filter nothing useful.
    static let minimumFilterOptions = 2
}

public extension SharedFeature {
    /// What the people row above the list narrows to. Kept per segment.
    enum Filter: Hashable, Sendable {
        case all
        /// By me only: items with a public link.
        case anyone
        /// A recipient (By me) or a sharer (With me), by user id.
        case person(String)
    }

    /// One circle in the people row.
    struct FilterOption: Equatable, Identifiable, Sendable {
        public let filter: Filter
        /// The person's display name; empty for All and Anyone.
        public let name: String
        /// Items this option keeps.
        public let count: Int

        public var id: Filter {
            filter
        }
    }

    /// A recipient or sharer drawn as an avatar.
    struct Person: Equatable, Identifiable, Sendable {
        public let id: String
        public let name: String
    }

    /// An expiry worth showing on a row: close enough to warn about, or past.
    enum ExpiryNotice: Equatable, Sendable {
        case daysLeft(Int)
        case expired
    }

    /// One share on an item row: who it reaches and how close it is to expiring.
    struct ShareBadge: Equatable, Identifiable, Sendable {
        public let id: Share.ID
        public let isAnyone: Bool
        /// Named recipients (By me) or the sharer (With me).
        public let people: [Person]
        /// Recipients whose name has not resolved yet.
        public let unnamedCount: Int
        public let expiry: ExpiryNotice?
    }

    /// A shared file or folder with every share on it. By me groups shares of the same path;
    /// With me has no path, so each share is its own item.
    struct Item: Equatable, Identifiable, Sendable {
        public let id: String
        public let name: String
        /// Parent folder path, nil at the root and for With me.
        public let location: String?
        public let shares: [Share]
        public let badges: [ShareBadge]
        /// Every share on it has expired.
        public let isExpired: Bool
    }

    /// Every instant a share's row text changes: the expiry itself and each whole day before
    /// it inside the warning window.
    static func expiryBoundaries(of expiresAt: Date) -> [Date] {
        (0 ... Constants.expiryWarningDays).map { expiresAt.addingTimeInterval(-Double($0) * Constants.secondsPerDay) }
    }
}

public extension SharedFeature.State {
    func filter(for segment: SharedFeature.Segment) -> SharedFeature.Filter {
        filters[segment] ?? .all
    }

    func expiryNotice(for share: Share) -> SharedFeature.ExpiryNotice? {
        guard let expiresAt = share.expiresAt else { return nil }
        if expiresAt <= now {
            return .expired
        }
        let days = Int((expiresAt.timeIntervalSince(now) / Constants.secondsPerDay).rounded(.up))
        return days <= Constants.expiryWarningDays ? .daysLeft(days) : nil
    }

    /// The searched and sorted list, narrowed by the segment's filter and grouped into items,
    /// fully expired items last.
    func items(for segment: SharedFeature.Segment) -> [SharedFeature.Item] {
        let filter = filter(for: segment)
        let groups = grouped(
            displayedShares(for: segment).filter { Self.matches($0, filter: filter, segment: segment) },
            segment: segment
        )
        let items = groups.map { key, shares in item(id: key, shares: shares, segment: segment) }
        return items.filter { !$0.isExpired } + items.filter(\.isExpired)
    }

    /// All, then Anyone (By me), then each named person by item count. Built from the whole
    /// segment, not the search, so typing never drops the active filter.
    func filterOptions(for segment: SharedFeature.Segment) -> [SharedFeature.FilterOption] {
        let groups = grouped(Array(shares(for: segment)), segment: segment)
        var anyoneCount = 0
        var personCounts: [String: Int] = [:]
        for (_, shares) in groups {
            if segment == .byMe, shares.contains(where: { $0.sharingType == .anyone }) {
                anyoneCount += 1
            }
            for id in Set(shares.flatMap { personIDs(of: $0, segment: segment) }) where userNames[id] != nil {
                personCounts[id, default: 0] += 1
            }
        }
        var people: [SharedFeature.FilterOption] = []
        for (id, count) in personCounts {
            if let name = userNames[id] {
                people.append(SharedFeature.FilterOption(filter: .person(id), name: name, count: count))
            }
        }
        people.sort { lhs, rhs in
            guard lhs.count == rhs.count else { return lhs.count > rhs.count }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        let anyone = anyoneCount > 0 ? [SharedFeature.FilterOption(filter: .anyone, name: "", count: anyoneCount)] : []
        return [SharedFeature.FilterOption(filter: .all, name: "", count: groups.count)] + anyone + people
    }

    /// Hidden while it could narrow to nothing useful, unless a filter is already active.
    func isFilterRowVisible(for segment: SharedFeature.Segment) -> Bool {
        filter(for: segment) != .all || filterOptions(for: segment).count > Constants.minimumFilterOptions
    }

    /// Drops a filter whose person or public link no longer exists after a reload or delete.
    mutating func pruneFilters() {
        for (segment, filter) in filters where !filterOptions(for: segment).contains(where: { $0.filter == filter }) {
            filters[segment] = nil
        }
    }

    private static func matches(
        _ share: Share,
        filter: SharedFeature.Filter,
        segment: SharedFeature.Segment
    ) -> Bool {
        switch filter {
        case .all:
            true
        case .anyone:
            share.sharingType == .anyone
        case let .person(id):
            segment == .byMe ? (share.permittedUserIds ?? []).contains(id) : share.ownerId == id
        }
    }

    private func personIDs(of share: Share, segment: SharedFeature.Segment) -> [String] {
        segment == .byMe ? share.permittedUserIds ?? [] : [share.ownerId]
    }

    /// Shares keyed by item, in first appearance order.
    private func grouped(_ shares: [Share], segment: SharedFeature.Segment) -> [(String, [Share])] {
        var order: [String] = []
        var groups: [String: [Share]] = [:]
        for share in shares {
            let key = itemKey(of: share, segment: segment)
            if groups[key] == nil {
                order.append(key)
            }
            groups[key, default: []].append(share)
        }
        return order.compactMap { key in groups[key].map { (key, $0) } }
    }

    private func itemKey(of share: Share, segment: SharedFeature.Segment) -> String {
        guard segment == .byMe, let path = Self.trimmedPath(share), !path.isEmpty else { return share.id }
        return "\(share.sourceSpace ?? ""):\(path)"
    }

    private static func trimmedPath(_ share: Share) -> String? {
        share.sourcePath?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func item(id: String, shares: [Share], segment: SharedFeature.Segment) -> SharedFeature.Item {
        let ordered = shares.sorted { $0.createdAt < $1.createdAt }
        let first = ordered[0]
        let components = Self.trimmedPath(first)?.split(separator: "/").map(String.init) ?? []
        let name: String = if segment == .byMe, let leaf = components.last {
            leaf
        } else if let sourceName = first.sourceName, !sourceName.isEmpty {
            sourceName
        } else {
            first.displayName
        }
        let parent = components.dropLast().joined(separator: "/")
        return SharedFeature.Item(
            id: id,
            name: name,
            location: segment == .byMe && !parent.isEmpty ? parent : nil,
            shares: ordered,
            badges: ordered.map { badge(for: $0, segment: segment) },
            isExpired: ordered.allSatisfy(isExpired)
        )
    }

    private func badge(for share: Share, segment: SharedFeature.Segment) -> SharedFeature.ShareBadge {
        let people: [SharedFeature.Person]
        let unnamed: Int
        if segment == .withMe {
            people = [SharedFeature.Person(id: share.ownerId, name: sharedByLabel(for: share))]
            unnamed = 0
        } else {
            let ids = share.sharingType == .users ? share.permittedUserIds ?? [] : []
            people = ids.compactMap { id in userNames[id].map { SharedFeature.Person(id: id, name: $0) } }
            unnamed = ids.count - people.count
        }
        return SharedFeature.ShareBadge(
            id: share.id,
            isAnyone: segment == .byMe && share.sharingType == .anyone,
            people: people,
            unnamedCount: unnamed,
            expiry: expiryNotice(for: share)
        )
    }
}
