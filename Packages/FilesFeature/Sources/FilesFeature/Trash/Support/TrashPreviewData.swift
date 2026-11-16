import ComposableArchitecture
import CoreModels
import Foundation

/// Fixed trash contents for previews: one of each kind of row the screens draw.
enum TrashPreviewData {
    private enum Constants {
        static let deletedAt = Date(timeIntervalSince1970: 1_763_200_000)
        static let day: TimeInterval = 86400
        static let retentionDays = 30
    }

    static let serverURL = URL(string: "https://files.example.com")!

    static let items: [TrashItem] = [
        TrashItem(
            id: "t1",
            name: "Quarterly report.pdf",
            size: 2_400_000,
            deletedAt: Constants.deletedAt,
            expiresAt: Constants.deletedAt.addingTimeInterval(Double(Constants.retentionDays) * Constants.day),
            deletedBy: .init(label: "Ada", isYou: true),
            location: .init(isPersonal: true, name: "ada", parent: "Reports"),
            openPath: "personal/Reports",
            shareCount: 2
        ),
        TrashItem(
            id: "t2",
            name: "Holiday photos",
            isDirectory: true,
            size: 812_000_000,
            deletedAt: Constants.deletedAt,
            expiresAt: Constants.deletedAt.addingTimeInterval(3 * Constants.day),
            deletedBy: .init(label: "Grace", isYou: false),
            location: .init(isPersonal: false, name: "Media", parent: "2025"),
            openPath: "Media/2025"
        ),
        TrashItem(
            id: "t3",
            name: "notes.txt",
            size: 512,
            deletedAt: Constants.deletedAt,
            expiresAt: Constants.deletedAt,
            deletedBy: .init(label: TrashItem.DeletedBy.shareLinkLabel, isYou: false),
            location: .init(isPersonal: false, name: "Archive", parent: ""),
            isAvailable: false
        ),
    ]

    static let entries: [TrashEntry] = [
        TrashEntry(name: "Summer", isDirectory: true, shareCount: 1),
        TrashEntry(name: "beach.jpg", size: 1_024_000, modifiedAt: Constants.deletedAt),
        TrashEntry(name: "itinerary.md", size: 2048, modifiedAt: Constants.deletedAt),
    ]

    static func trash(_ configure: (inout TrashFeature.State) -> Void = { _ in }) -> StoreOf<TrashFeature> {
        var state = TrashFeature.State(serverURL: serverURL)
        state.phase = .loaded
        state.items = IdentifiedArray(uniqueElements: items)
        state.retentionDays = Constants.retentionDays
        configure(&state)
        return Store(initialState: state) { EmptyReducer() }
    }

    static func folder(_ configure: (inout TrashFolderFeature.State) -> Void = { _ in
    }) -> StoreOf<TrashFolderFeature> {
        var state = TrashFolderFeature.State(serverURL: serverURL, item: items[1])
        state.phase = .loaded
        state.entries = IdentifiedArray(uniqueElements: entries)
        configure(&state)
        return Store(initialState: state) { EmptyReducer() }
    }
}
