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
        /// Recipients (By me) or sharers (With me), by user id. By me keeps the shares that reach
        /// every one of them; With me keeps what any of them shared, as each share has one sharer.
        case people(Set<String>)
    }

    /// One circle in the people row.
    struct FilterOption: Equatable, Identifiable, Sendable {
        public let filter: Filter
        /// The person's display name; empty for All and Anyone.
        public let name: String
        /// Items this option keeps.
        public let count: Int
        /// A person no share reaches together with the people already picked; tapping them
        /// starts a new pick instead of joining it.
        public var isDimmed = false

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

    /// The open detail sheet: which item, and the share pushed over its list when it has several.
    /// Identified by the item alone, so pushing or popping never presents the sheet again.
    struct Detail: Equatable, Identifiable, Sendable {
        public let segment: Segment
        public let id: Item.ID
        public var pushedShareID: Share.ID?

        public init(segment: Segment, id: Item.ID, pushedShareID: Share.ID? = nil) {
            self.segment = segment
            self.id = id
            self.pushedShareID = pushedShareID
        }
    }

    /// Every instant a share's row text changes: the expiry itself and each whole day before
    /// it inside the warning window.
    static func expiryBoundaries(of expiresAt: Date) -> [Date] {
        (0 ... Constants.expiryWarningDays).map { expiresAt.addingTimeInterval(-Double($0) * Constants.secondsPerDay) }
    }
}

public extension SharedFeature.Item {
    /// Downloads across every share on it.
    var downloadCount: Int {
        shares.reduce(0) { $0 + $1.downloadCount }
    }

    /// The latest open across every share on it.
    var lastOpenedAt: Date? {
        shares.compactMap(\.lastAccessedAt).max()
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

    /// The share whose expiry speaks for the item: the live one ending soonest, or the last to
    /// end once every share has expired. Nil when no live share has a date.
    func nearestExpiringShare(in item: SharedFeature.Item) -> Share? {
        let dated = item.shares.compactMap { share in share.expiresAt.map { (share, $0) } }
        if item.isExpired {
            return dated.max { $0.1 < $1.1 }?.0
        }
        return dated.filter { !isExpired($0.0) }.min { $0.1 < $1.1 }?.0
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
        var picked: Set<String> = []
        if segment == .byMe, case let .people(ids) = filter(for: segment) {
            picked = ids
        }
        var people: [SharedFeature.FilterOption] = []
        for (id, count) in personCounts {
            if let name = userNames[id] {
                people.append(SharedFeature.FilterOption(
                    filter: .people([id]),
                    name: name,
                    count: count,
                    isDimmed: !picked.isEmpty && !picked.contains(id) && !hasCommonShare(picked.union([id]))
                ))
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

    /// What a tap on a people row option leaves active. A person joins, or leaves, the people
    /// already picked; on By me only while one share still reaches them all. Otherwise the tap
    /// replaces the filter, and tapping the only active choice again clears it back to All.
    func filter(afterTapping tapped: SharedFeature.Filter, in segment: SharedFeature.Segment) -> SharedFeature.Filter {
        let current = filter(for: segment)
        if tapped == current {
            return .all
        }
        guard case let .people(picked) = current, case let .people(ids) = tapped else {
            return tapped
        }
        let combined = picked.symmetricDifference(ids)
        if combined.isEmpty {
            return .all
        }
        return segment == .withMe || hasCommonShare(combined) ? .people(combined) : tapped
    }

    /// Drops a filter whose people or public link no longer exist after a reload or delete,
    /// and fits the open detail sheet to what is left.
    mutating func sharesChanged() {
        for (segment, filter) in filters where !isStillValid(filter, in: segment) {
            filters[segment] = nil
        }
        reconcileDetail()
    }

    private func isStillValid(_ filter: SharedFeature.Filter, in segment: SharedFeature.Segment) -> Bool {
        let options = filterOptions(for: segment)
        guard case let .people(ids) = filter else {
            return options.contains { $0.filter == filter }
        }
        let known = Set(options.compactMap(\.filter.personID))
        return ids.isSubset(of: known) && (segment == .withMe || hasCommonShare(ids))
    }

    /// Whether one By me share reaches every one of these people.
    private func hasCommonShare(_ ids: Set<String>) -> Bool {
        shares(for: .byMe).contains { ids.isSubset(of: $0.permittedUserIds ?? []) }
    }

    /// The item behind a detail sheet with every share on it, ignoring the search and the people
    /// row, so the sheet never hides a share the row filtered out.
    func item(for detail: SharedFeature.Detail) -> SharedFeature.Item? {
        grouped(Array(shares(for: detail.segment)), segment: detail.segment)
            .first { $0.0 == detail.id }
            .map { item(id: $0.0, shares: $0.1, segment: detail.segment) }
    }

    /// Closes the sheet once its item is gone; pops the pushed share once it is gone or is the
    /// only one left, since the root then opens straight on it.
    private mutating func reconcileDetail() {
        if let editing = editSheet, byMe[id: editing.share.id] == nil {
            editSheet = nil
        }
        guard let detail else { return }
        guard let item = item(for: detail) else {
            self.detail = nil
            return
        }
        if let pushed = detail.pushedShareID,
           item.shares.count < 2 || !item.shares.contains(where: { $0.id == pushed })
        {
            self.detail?.pushedShareID = nil
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
        case let .people(ids) where segment == .byMe:
            ids.isSubset(of: share.permittedUserIds ?? [])
        case let .people(ids):
            ids.contains(share.ownerId)
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
        guard segment == .byMe, let path = share.trimmedSourcePath, !path.isEmpty else { return share.id }
        return "\(share.sourceSpace ?? ""):\(path)"
    }

    private func item(id: String, shares: [Share], segment: SharedFeature.Segment) -> SharedFeature.Item {
        let ordered = shares.sorted { $0.createdAt < $1.createdAt }
        let first = ordered[0]
        let parent = first.itemLocation
        return SharedFeature.Item(
            id: id,
            name: segment == .withMe ? first.displayName : first.itemName,
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
