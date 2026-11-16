import CoreModels
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite("Trash row text")
struct TrashRowTextTests {
    private enum Constants {
        static let day: TimeInterval = 86400
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    @Test("The second line leads with reach and removal, then who, where and the share badge")
    func subtitleOrder() {
        let item = TrashItem(
            id: "t1",
            name: "a.txt",
            expiresAt: MockDate.date.addingTimeInterval(2 * Constants.day),
            deletedBy: .init(label: "Ada", isYou: false),
            location: .init(isPersonal: false, name: "Media", parent: "2025"),
            isAvailable: false,
            shareCount: 1
        )

        let subtitle = TrashRowText.subtitle(item, now: MockDate.date, calendar: calendar)

        #expect(subtitle == [
            L10n.Trash.unavailable, L10n.Trash.removedIn(2), L10n.Trash.deletedBy("Ada"), "Media/2025",
            L10n.Trash.sharesBadge,
        ].joined(separator: TrashRowText.separator))
    }

    @Test("Locations name the personal folder, a volume root, or say they are unknown")
    func locations() {
        #expect(TrashRowText.location(TrashItem(
            id: "a",
            name: "a",
            location: .init(isPersonal: true, name: "ada", parent: "")
        ))
            == L10n.Trash.locationPersonal)
        #expect(TrashRowText.location(TrashItem(
            id: "b",
            name: "b",
            location: .init(isPersonal: false, name: "Media", parent: "")
        ))
            == "Media")
        #expect(TrashRowText.location(TrashItem(id: "c", name: "c")) == L10n.Trash.locationUnknown)
    }

    @Test("Who deleted it: you, a share link, an account, or unknown")
    func deleters() {
        #expect(TrashRowText
            .deletedBy(TrashItem(id: "a", name: "a", deletedBy: .init(label: "Ada", isYou: true))) == L10n.Trash
            .deletedByYou)
        #expect(TrashRowText.deletedBy(TrashItem(
            id: "b",
            name: "b",
            deletedBy: .init(label: TrashItem.DeletedBy.shareLinkLabel, isYou: false)
        ))
            == L10n.Trash.deletedByShareLink)
        #expect(TrashRowText
            .deletedBy(TrashItem(id: "c", name: "c", deletedBy: .init(label: "Grace", isYou: false))) == "Grace")
        #expect(TrashRowText.deletedBy(TrashItem(id: "d", name: "d", deletedBy: .init(label: "", isYou: false))) == L10n
            .Trash.deletedByUnknown)
    }
}
