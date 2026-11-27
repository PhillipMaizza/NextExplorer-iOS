#if os(macOS)
    @testable import DesignSystem
    import Testing

    @Suite("Mac action menu")
    struct MacActionMenuTests {
        @Test("a divider only stands between two rows", arguments: [
            ("-a", "a"),
            ("a-", "a"),
            ("a--b", "a-b"),
            ("-a-b-", "a-b"),
            ("--", ""),
            ("ab-c", "ab-c"),
        ])
        func dividersOnlyBetweenRows(rows: String, shown: String) {
            #expect(String(Array(rows).separated { $0 == "-" }) == shown)
        }
    }
#endif
