import Testing

@testable import CoreModels

@Suite
struct OfficeEditorTests {
    private func editors(
        onlyOffice: Bool = false,
        onlyOfficeExtensions: [String] = [],
        collabora: Bool = false,
        collaboraExtensions: [String] = []
    ) -> ServerFeatures.OfficeEditors {
        ServerFeatures.OfficeEditors(
            isOnlyOfficeEnabled: onlyOffice,
            onlyOfficeExtensions: onlyOfficeExtensions,
            isCollaboraEnabled: collabora,
            collaboraExtensions: collaboraExtensions
        )
    }

    @Test
    func neitherEnabledMeansNoEditor() {
        #expect(OfficeEditorSupport.editor(for: "docx", features: editors()) == nil)
    }

    @Test
    func bothEnabledPrefersOnlyOffice() {
        let result = OfficeEditorSupport.editor(for: "xlsx", features: editors(onlyOffice: true, collabora: true))
        #expect(result == .onlyOffice)
    }

    @Test
    func collaboraUsedWhenItIsTheOnlyOneEnabled() {
        #expect(OfficeEditorSupport.editor(for: "odt", features: editors(collabora: true)) == .collabora)
    }

    @Test
    func anEmptyAdvertisedListFallsBackToTheDefaultSet() {
        #expect(OfficeEditorSupport.editor(for: "pptx", features: editors(onlyOffice: true)) == .onlyOffice)
    }

    @Test
    func anAdvertisedListNarrowsWhatOpens() {
        let features = editors(onlyOffice: true, onlyOfficeExtensions: ["docx"])
        #expect(OfficeEditorSupport.editor(for: "docx", features: features) == .onlyOffice)
        #expect(OfficeEditorSupport.editor(for: "xlsx", features: features) == nil)
    }

    @Test
    func extensionMatchIsCaseInsensitive() {
        #expect(OfficeEditorSupport.editor(for: "DOCX", features: editors(onlyOffice: true)) == .onlyOffice)
    }

    @Test
    func txtOpensInCollaboraButNotOnlyOfficeByDefault() {
        #expect(OfficeEditorSupport.editor(for: "txt", features: editors(onlyOffice: true)) == nil)
        #expect(OfficeEditorSupport.editor(for: "txt", features: editors(collabora: true)) == .collabora)
    }

    @Test
    func anUnknownExtensionNeverMatches() {
        #expect(OfficeEditorSupport.editor(for: "psd", features: editors(onlyOffice: true, collabora: true)) == nil)
    }
}
