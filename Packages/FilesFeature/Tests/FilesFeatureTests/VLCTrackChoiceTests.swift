@testable import FilesFeature
import Foundation
import Testing

@MainActor
struct VLCTrackChoiceTests {
    @Test
    func namesAndIndexesPairUp() {
        let tracks = VLCPlaybackController.choices(
            names: ["Disable", "English", "Français"],
            ids: [NSNumber(value: -1), NSNumber(value: 3), NSNumber(value: 4)]
        )

        #expect(tracks.map(\.id) == [-1, 3, 4])
        #expect(tracks.map(\.name) == ["Disable", "English", "Français"])
    }

    @Test
    func missingOrMismatchedListsGiveNoTracks() {
        #expect(VLCPlaybackController.choices(names: nil, ids: nil).isEmpty)
        #expect(VLCPlaybackController.choices(names: ["A"], ids: ["x"]).isEmpty)
    }
}
