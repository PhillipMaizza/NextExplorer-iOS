#if os(macOS)
    @testable import FilesFeature
    import Foundation
    import Testing

    struct PrettyTextTests {
        private func text(_ fixture: FilesFeatureFixture) throws -> String {
            try fixture.string().trimmingCharacters(in: .newlines)
        }

        @Test("Compact JSON is indented in its own key order, strings untouched")
        func compactJSONIsIndentedInItsOwnKeyOrder() throws {
            #expect(try PrettyText.format(text(.prettyCompact), kind: "JSON") == text(.prettyCompactLaidOut))
        }

        @Test("Escaped quotes inside a string stay inside it")
        func escapedQuotesStayInsideTheString() throws {
            #expect(try PrettyText.format(text(.prettyEscaped), kind: "json") == text(.prettyEscapedLaidOut))
        }

        @Test("JSON crammed onto a few lines is laid out again")
        func crampedJSONIsLaidOutAgain() throws {
            let pretty = try #require(PrettyText.format(text(.prettyCramped), kind: "json"))

            #expect(pretty.contains("\n  \"limits\": {\n    \"mb\": 512,"))
        }

        @Test("Already indented, invalid, empty or other kinds are left as they are")
        func indentedInvalidOrOtherKindsAreLeftAlone() throws {
            #expect(try PrettyText.format(text(.prettyIndented), kind: "json") == nil)
            #expect(try PrettyText.format(text(.prettyTruncated), kind: "json") == nil)
            #expect(PrettyText.format("", kind: "json") == nil)
            #expect(try PrettyText.format(text(.prettyCompact), kind: "txt") == nil)
        }

        @Test("Compact XML is indented, even after a declaration line")
        func compactXMLIsIndented() throws {
            let compact = "<?xml version=\"1.0\"?>\n<root><item id=\"1\">One</item><item id=\"2\">Two</item></root>"
            let pretty = try #require(PrettyText.format(compact, kind: "xml"))

            #expect(pretty.hasPrefix("<?xml version=\"1.0\"?>\n<root>\n"))
            #expect(pretty.contains("\n    <item id=\"1\">One</item>"))
            #expect(PrettyText.format("<root>\n  <a/>\n</root>", kind: "xml") == nil)
            #expect(PrettyText.format("<root><a></root>", kind: "xml") == nil)
        }
    }
#endif
