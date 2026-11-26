@testable import DesignSystem
import Localization
import Testing

struct PersonalSpaceTrailTests {
    @Test("A received share's code never shows: its root reads as Shared with Me")
    func receivedShareHidesItsCode() {
        #expect(PersonalSpace.folderTitle("share/CEDGWfwhCZ") == L10n.Shared.sharedWithMe)
        #expect(PersonalSpace.trail("share/CEDGWfwhCZ/PDF") == PathTrail.text("\(L10n.Shared.sharedWithMe)/PDF"))
    }

    @Test("The personal space still reads as My Files")
    func personalSpace() {
        #expect(PersonalSpace.folderTitle("personal") == L10n.Browse.myFiles)
        #expect(PersonalSpace.trail("personal/Docs") == PathTrail.text("\(L10n.Browse.myFiles)/Docs"))
    }
}
