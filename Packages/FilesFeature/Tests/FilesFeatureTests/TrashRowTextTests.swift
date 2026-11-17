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

    @Test("The details lead with reach, time left, who and the share badge, then the folder on its own line")
    func subtitleOrder() throws {
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

        let lines = subtitle.components(separatedBy: "\n")
        let parts = try #require(lines.first).components(separatedBy: TrashRowText.separator)
        #expect(lines.count == 2)
        #expect(lines.last == "Media/2025")
        #expect(parts.count == 4)
        #expect(parts[0] == L10n.Trash.unavailable)
        #expect(parts[1].contains("2"))
        #expect(parts[2] == L10n.Trash.deletedBy("Ada"))
        #expect(parts[3] == L10n.Trash.sharesBadge)
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
