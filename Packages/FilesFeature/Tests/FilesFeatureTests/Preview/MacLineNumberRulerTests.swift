#if os(macOS)
    @testable import FilesFeature
    import Testing

    struct MacLineNumberRulerTests {
        @Test("Each line starts after a newline, and an offset maps to the line that holds it")
        func offsetsMapToTheirLine() {
            let starts = MacLineNumberRuler.lineStarts(in: "ab\n\ncd\n")

            #expect(starts == [0, 3, 4, 7])
            #expect(MacLineNumberRuler.lineNumber(atOffset: 0, lineStarts: starts) == 1)
            #expect(MacLineNumberRuler.lineNumber(atOffset: 2, lineStarts: starts) == 1)
            #expect(MacLineNumberRuler.lineNumber(atOffset: 3, lineStarts: starts) == 2)
            #expect(MacLineNumberRuler.lineNumber(atOffset: 5, lineStarts: starts) == 3)
            #expect(MacLineNumberRuler.lineNumber(atOffset: 7, lineStarts: starts) == 4)
        }

        @Test("Text with no newline is one line")
        func textWithoutNewlinesIsOneLine() {
            let starts = MacLineNumberRuler.lineStarts(in: "")

            #expect(starts == [0])
            #expect(MacLineNumberRuler.lineNumber(atOffset: 0, lineStarts: starts) == 1)
        }
    }
#endif
