import Testing
import TestUtils

@Suite("Fixture files")
struct FixtureAuditTests {
    @Test("every fixture case has a file and every file has a case")
    func fixturesMatchTheEnum() {
        let result = ShareExtensionFixture.audit()
        #expect(result.missing.isEmpty)
        #expect(result.orphans.isEmpty)
    }
}
