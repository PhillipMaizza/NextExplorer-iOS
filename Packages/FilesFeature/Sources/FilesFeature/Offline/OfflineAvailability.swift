import Foundation

/// Which entries are kept on the device: a pinned item, anything below a pinned folder, or a file
/// with a stored copy. Shared by the folder badges and the search sections, so both agree.
enum OfflineAvailability {
    /// `all` holds every entry on the device, `pinned` the subset the user pinned themselves.
    /// Reads the store through `hasCopy`, so call it off the main actor.
    nonisolated static func classify<Entry>(
        _ entries: [Entry],
        pinnedPaths: [String],
        id: (Entry) -> String,
        isDirectory: (Entry) -> Bool,
        hasCopy: (Entry) -> Bool
    ) -> (all: Set<String>, pinned: Set<String>) {
        let pinnedSet = Set(pinnedPaths)
        let prefixes = pinnedPaths.map { $0 + "/" }
        var all = Set<String>()
        var pinned = Set<String>()
        for entry in entries {
            let entryID = id(entry)
            if pinnedSet.contains(entryID) {
                pinned.insert(entryID)
                all.insert(entryID)
            } else if prefixes.contains(where: { entryID.hasPrefix($0) }) || (!isDirectory(entry) && hasCopy(entry)) {
                all.insert(entryID)
            }
        }
        return (all, pinned)
    }
}
