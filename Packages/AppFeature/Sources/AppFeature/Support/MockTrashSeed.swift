#if DEBUG
    import CoreModels
    import Foundation

    extension MockBrowseTree {
        typealias TrashEntry = UITestFixture.TrashEntry

        /// What the trash holds at launch, newest first: one item per state a trash row shows.
        static func trash(now: Date) -> [MockFileTree.Trashed] {
            let retention = Double(UITestSupport.trashRetentionDays) * Age.day
            func trashed(
                _ entry: TrashEntry,
                from folder: Folder?,
                deletedAgo: TimeInterval,
                deletedBy: TrashItem.DeletedBy = TrashItem.DeletedBy(label: nil, isYou: true),
                location: TrashItem.Location? = nil,
                isAvailable: Bool = true,
                shareCount: Int = 0,
                isFolder: Bool = false,
                size: Int64 = 0,
                subtree: [String: [FileItem]] = [:],
                texts: [String: String] = [:]
            ) -> MockFileTree.Trashed {
                let parent = folder?.path ?? ""
                let deletedAt = now.addingTimeInterval(-deletedAgo)
                let original = (isFolder
                    ? Entry(name: entry.name, size: 0, age: deletedAgo, isFolder: true, hasThumbnail: false)
                    : Entry.generated(entry.name, size, age: deletedAgo)
                ).item(in: parent, now: now)
                return MockFileTree.Trashed(
                    item: TrashItem(
                        id: "seeded-\(entry)",
                        name: entry.name,
                        isDirectory: isFolder,
                        size: isFolder ? nil : size,
                        deletedAt: deletedAt,
                        expiresAt: deletedAt.addingTimeInterval(retention),
                        deletedBy: deletedBy,
                        location: location ?? .mockVolume(parent),
                        openPath: parent,
                        isAvailable: isAvailable,
                        shareCount: shareCount
                    ),
                    original: original,
                    subtree: subtree,
                    texts: texts
                )
            }

            let photosPath = "\(Folder.photos.path)/\(TrashEntry.oldPhotos.name)"
            let shotList = UITestFixture.TrashedPhotosEntry.shotList
            return [
                trashed(.oldPhotos, from: .photos, deletedAgo: 2 * Age.hour, isFolder: true, subtree: [
                    photosPath: UITestFixture.TrashedPhotosEntry.allCases.map {
                        Entry.generated($0.name, $0 == shotList ? Size.kilobyte : 3 * Size.megabyte, age: Age.week)
                            .item(in: photosPath, now: now)
                    },
                ], texts: [shotList.name: UITestFixture.TrashedPhotosEntry.shotListText]),
                trashed(
                    .sharedPlan,
                    from: .documents,
                    deletedAgo: 3 * Age.day,
                    deletedBy: TrashItem.DeletedBy(label: TrashEntry.otherPerson.displayName, isYou: false),
                    shareCount: 2,
                    size: 400 * Size.kilobyte
                ),
                trashed(
                    .dropped,
                    from: .projects,
                    deletedAgo: 10 * Age.day,
                    deletedBy: TrashItem.DeletedBy(label: TrashItem.DeletedBy.shareLinkLabel, isYou: false),
                    size: 2 * Size.kilobyte,
                    texts: ["": TrashEntry.droppedText]
                ),
                trashed(
                    .offlineArchive,
                    from: nil,
                    deletedAgo: 20 * Age.day,
                    location: TrashItem.Location(
                        isPersonal: false,
                        name: TrashEntry.offlineVolume.rawValue,
                        parent: ""
                    ),
                    isAvailable: false,
                    size: 80 * Size.megabyte
                ),
                // Expires at launch, so it reads "removed today" at any hour.
                trashed(.oldBudget, from: .documents, deletedAgo: retention, size: 60 * Size.kilobyte),
            ]
        }
    }
#endif
