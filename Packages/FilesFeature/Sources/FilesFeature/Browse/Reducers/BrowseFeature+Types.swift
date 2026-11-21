import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import FolderPickerFeature
import Foundation
import Localization
import NetworkClient
import ShareUploads
import SwiftUI

public extension BrowseFeature {
    /// Effect timing/limits shared by `body` and the extracted `BrowseFeature+*.swift` effect
    /// helpers. Nested (not a file private top level enum) so those extensions can see it.
    internal enum Constants {
        /// After a copy or move into the folder on screen, how many extra refetches wait for the
        /// new items to be listed, and how far apart. A server that finishes the copy after
        /// answering (or a listing fetched a moment too early) otherwise leaves the new
        /// "Name (2)" missing until a manual refresh.
        static let arrivalRechecks = 3
        static let arrivalRecheckDelay: Duration = .milliseconds(700)
        /// An action taken from a full screen preview that also dismisses the cover (delete,
        /// "Open" on the download toast, "View in Shared") waits this long before it runs, so the
        /// cover finishes dismissing first and the effect: a row sliding out, a tab switch:
        /// plays on the list the user is now looking at, not mid transition.
        static let previewActionSettleDelay: Duration = .milliseconds(350)
        /// How long the Mac inspector waits on a newly selected row before loading it.
        static let inspectorFollowDelay: Duration = .milliseconds(200)
        /// Most folders warmed into the offline cache per prefetch pass, so opening a folder with
        /// hundreds of subfolders doesn't fan out hundreds of listings.
        static let maxPrefetchedFolders = 20
        /// Favorites are warmed on their own budget so subfolders never use it up.
        static let maxPrefetchedFavorites = 40
        /// Gateway and proxy answers (bad gateway, unavailable, gateway timeout, and Cloudflare's
        /// origin timeout) that say nothing about whether a slow mutation finished on the server.
        static let ambiguousMutationStatuses: Set<Int> = [502, 503, 504, 524]
        /// The status a replace reports when the trash kept what it was replacing (a conflict).
        static let replaceRefusedStatus = 409
    }

    /// Where `.searchable`'s scope bar points the search request. "This Folder" is
    /// answered instantly from `items`, already loaded client side, so no network round
    /// trip or debounce is needed. "Everywhere" mirrors the web client's own root search
    /// (`backend/src/routes/search.js`) and still needs one.
    enum SearchScope: Hashable, Sendable, CaseIterable {
        case thisFolder, everywhere

        var title: String {
            switch self {
            case .thisFolder: L10n.Browse.scopeThisFolder
            case .everywhere: L10n.Browse.scopeEverywhere
            }
        }
    }

    /// How `displayedItems` orders a folder's contents. Folders always sort before files
    /// regardless of option; this only decides the order within each of those two groups.
    enum SortOption: String, Hashable, Sendable, CaseIterable {
        case name, size, dateModified, kind

        var title: String {
            switch self {
            case .name: L10n.Sort.name
            case .size: L10n.Sort.size
            case .dateModified: L10n.Sort.dateModified
            case .kind: L10n.Sort.kind
            }
        }

        var icon: Image {
            switch self {
            case .name: IconKit.textformat
            case .size: IconKit.size
            case .dateModified: IconKit.calendar
            case .kind: IconKit.tag
            }
        }
    }

    /// Which way `sortOption` orders each group. Applies uniformly regardless of option:
    /// e.g. `.size` + `.ascending` is smallest first, `.size` + `.descending` is largest first.
    enum SortDirection: String, Hashable, Sendable, CaseIterable {
        case ascending, descending

        var title: String {
            switch self {
            case .ascending: L10n.Sort.ascending
            case .descending: L10n.Sort.descending
            }
        }

        var icon: Image {
            switch self {
            case .ascending: IconKit.sortAscending
            case .descending: IconKit.sortDescending
            }
        }
    }

    struct FavoriteToggleResult: Equatable, Sendable {
        public let path: String
        public let isFavorite: Bool
    }

    struct RenameResult: Equatable, Sendable {
        public let originalID: String
        public let renamed: FileItem
    }

    /// What a delete did: the rows to drop, the items the trash refused (still on disk), and how
    /// many went to the trash rather than away for good.
    struct DeleteResult: Equatable, Sendable {
        public let removedIDs: [FileItem.ID]
        public let kept: [KeptDelete]
        public let trashedCount: Int

        public init(removedIDs: [FileItem.ID], kept: [KeptDelete] = [], trashedCount: Int = 0) {
            self.removedIDs = removedIDs
            self.kept = kept
            self.trashedCount = trashedCount
        }

        /// Pairs the server's answers with the request by position, as it answers in order.
        init(requested: [FileItem], outcome: DeleteOutcome) {
            let kept = zip(requested, outcome.items).compactMap { item, entry in
                entry.status == .kept
                    ? KeptDelete(item: item, reason: entry.reason, size: entry.size, budgetBytes: entry.budgetBytes)
                    : nil
            }
            let keptIDs = Set(kept.map(\.id))
            self.init(
                removedIDs: requested.map(\.id).filter { !keptIDs.contains($0) },
                kept: kept,
                trashedCount: outcome.trashedCount
            )
        }
    }

    /// An item the trash would not take, left where it was.
    struct KeptDelete: Equatable, Sendable, Identifiable {
        public let item: FileItem
        public let reason: TrashRefusal?
        public let size: Int64?
        public let budgetBytes: Int64?

        public var id: FileItem.ID {
            item.id
        }
    }

    /// A delete sent `count` items to the trash; `sequence` makes each notice new, so the toast
    /// shows again for a second delete of the same size.
    struct MovedToTrashNotice: Equatable, Sendable {
        public let count: Int
        public let sequence: Int
    }

    /// State of the `POST /api/files/delete-impact` lookup that runs while a delete
    /// confirmation is on screen. `.unavailable` means the check itself failed: the delete
    /// still proceeds, the server still removes any linked shares, the alert just can't say
    /// how many.
    enum DeleteImpactCheck: Equatable, Sendable {
        case idle
        case checking
        case loaded(DeleteImpact)
        case unavailable
    }

    struct BulkFavoriteToggleResult: Equatable, Sendable {
        public let added: [String]
        public let removed: [String]
        public let failedCount: Int
        public let totalCount: Int

        public init(added: [String], removed: [String], failedCount: Int = 0, totalCount: Int? = nil) {
            self.added = added
            self.removed = removed
            self.failedCount = failedCount
            self.totalCount = totalCount ?? added.count + removed.count + failedCount
        }
    }

    /// The result of a `copy`/`move` transfer, plus whether this transfer should empty the
    /// shared clipboard once it succeeds: `move` always clears, `copy` clears unless the
    /// "Keep Items After Paste" setting is on.
    struct TransferOutcome: Equatable, Sendable {
        public let result: TransferResult
        public let operation: TransferOperation
        public let shouldClearClipboard: Bool
    }

    /// Everything needed to rerun a failed transfer from the "Retry" action on its toast, and
    /// to remember how a name collision prompt was answered so a retry doesn't ask again.
    struct TransferRetry: Equatable, Sendable {
        /// How a name collision at the destination should be handled. `.ask` means the check
        /// hasn't run yet; `.keepBoth` lets the server auto rename (`file (1).txt`); `.replace`
        /// deletes `itemsToReplace` first, then transfers onto the freed names.
        public enum Resolution: Equatable, Sendable { case ask, keepBoth, replace }

        public let items: [FileItem]
        public let destination: String
        public let operation: TransferOperation
        public let shouldClearClipboard: Bool
        public var resolution: Resolution = .ask
        public var itemsToReplace: [FileItem] = []

        func resolved(_ resolution: Resolution, replacing itemsToReplace: [FileItem] = []) -> TransferRetry {
            TransferRetry(
                items: items, destination: destination, operation: operation,
                shouldClearClipboard: shouldClearClipboard, resolution: resolution, itemsToReplace: itemsToReplace
            )
        }
    }

    /// A pending transfer that's blocked on the user answering a name collision prompt.
    struct TransferConflict: Equatable, Sendable {
        public let retry: TransferRetry
        /// The destination items that share a name with something being transferred: deleted
        /// first if the user picks "Replace".
        public let collidingItems: [FileItem]
        public var count: Int {
            collidingItems.count
        }

        public var firstName: String {
            collidingItems.first?.name ?? ""
        }
    }

    /// The answer to a name collision prompt. `nil` (in the action payload) is "Cancel".
    enum TransferConflictChoice: Equatable, Sendable { case replace, keepBoth }

    /// Where the currently displayed listing came from.
    enum DataSource: Equatable, Sendable {
        case live
        /// Served from the offline cache, stamped with when it was last fetched from the server.
        case cached(fetchedAt: Date)
    }
}
