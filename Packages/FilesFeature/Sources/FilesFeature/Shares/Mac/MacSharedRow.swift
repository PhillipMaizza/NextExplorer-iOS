import CoreModels
import Foundation

/// One row of the Mac Shared table: a shared item, or one share under an item that has several.
/// Platform neutral so its rules run in the package tests.
struct MacSharedRow: Identifiable {
    enum ID: Hashable {
        case item(SharedFeature.Item.ID)
        case share(Share.ID, item: SharedFeature.Item.ID)

        var itemID: SharedFeature.Item.ID {
            switch self {
            case let .item(id), let .share(_, id): id
            }
        }
    }

    let item: SharedFeature.Item
    /// The share a child row stands for; nil on an item row.
    let child: Share?
    /// The share whose expiry the row shows: a child's own, or the item's nearest
    /// (`SharedFeature.State.nearestExpiringShare`).
    let expiringShare: Share?
    /// Who shared it, for With me; empty for By me.
    let sharer: String

    init(item: SharedFeature.Item, child: Share? = nil, expiringShare: Share?, sharer: String = "") {
        self.item = item
        self.child = child
        self.expiringShare = expiringShare
        self.sharer = sharer
    }

    var id: ID {
        child.map { .share($0.id, item: item.id) } ?? .item(item.id)
    }

    /// What right click, double click and Delete act on: the child's share, or a single share
    /// item's own. Nil on an item with several shares, whose shares each have their own row.
    var share: Share? {
        child ?? (item.shares.count == 1 ? item.shares[0] : nil)
    }

    /// One child row per share, oldest first, only when the item has several.
    var children: [MacSharedRow]? {
        guard child == nil, item.shares.count > 1 else { return nil }
        return item.shares.map { MacSharedRow(item: item, child: $0, expiringShare: $0, sharer: sharer) }
    }

    private var shares: [Share] {
        child.map { [$0] } ?? item.shares
    }

    // The sort keys, one per column.

    var name: String {
        item.name
    }

    /// How many people its shares reach; a public link adds none.
    var recipientCount: Int {
        shares.reduce(0) { $0 + ($1.permittedUserIds?.count ?? 0) }
    }

    /// No expiry sorts after every date.
    var expirySortDate: Date {
        expiringShare?.expiresAt ?? .distantFuture
    }

    var lastOpenedAt: Date? {
        if let child {
            return child.lastAccessedAt
        }
        return item.lastOpenedAt
    }

    /// Never opened sorts before every date.
    var lastOpenedSortDate: Date {
        lastOpenedAt ?? .distantPast
    }

    var downloadCount: Int {
        child?.downloadCount ?? item.downloadCount
    }

    var createdAt: Date {
        shares[0].createdAt
    }
}
