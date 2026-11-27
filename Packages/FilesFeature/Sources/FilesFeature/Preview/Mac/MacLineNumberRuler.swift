#if os(macOS)
    import AppKit
    import DesignSystem
    import SwiftUI

    private enum Constants {
        static let thickness: CGFloat = .size56
        static let trailingGap: CGFloat = .space4
        static let fontScale: CGFloat = 0.9
    }

    final class MacLineNumberRuler: NSRulerView {
        private var lineStarts = [0]

        init(textView: NSTextView) {
            super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
            clientView = textView
            ruleThickness = Constants.thickness
            reloadLines()
        }

        @available(*, unavailable)
        required init(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        func reloadLines() {
            guard let textView = clientView as? NSTextView else { return }
            lineStarts = Self.lineStarts(in: textView.string)
            needsDisplay = true
        }

        nonisolated static func lineStarts(in text: String) -> [Int] {
            var starts = [0]
            for (offset, unit) in text.utf16.enumerated() where unit == 0x0A {
                starts.append(offset + 1)
            }
            return starts
        }

        nonisolated static func lineNumber(atOffset offset: Int, lineStarts: [Int]) -> Int {
            var low = 0
            var high = lineStarts.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if lineStarts[mid] <= offset {
                    low = mid
                } else {
                    high = mid - 1
                }
            }
            return low + 1
        }

        override func draw(_ dirtyRect: NSRect) {
            drawHashMarksAndLabels(in: dirtyRect)
        }

        override func drawHashMarksAndLabels(in _: NSRect) {
            guard let textView = clientView as? NSTextView,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer,
                  let font = textView.font
            else { return }
            let numberFont = NSFont.monospacedDigitSystemFont(
                ofSize: font.pointSize * Constants.fontScale,
                weight: .regular
            )
            let attributes: [NSAttributedString.Key: Any] = [
                .font: numberFont,
                .foregroundColor: NSColor(Color.secondaryText),
            ]
            let inset = textView.textContainerOrigin
            let top = convert(NSPoint.zero, from: textView).y + inset.y
            let visible = textView.visibleRect.offsetBy(dx: -inset.x, dy: -inset.y)
            let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
            func drawNumber(_ line: Int, below lineRect: NSRect) {
                let number = String(line) as NSString
                let baseline = top + lineRect.maxY + font.descender
                let origin = NSPoint(
                    x: ruleThickness - Constants.trailingGap - number.size(withAttributes: attributes).width,
                    y: baseline - numberFont.ascender
                )
                number.draw(at: origin, withAttributes: attributes)
            }
            var glyphIndex = glyphs.location
            while glyphIndex < NSMaxRange(glyphs) {
                var lineGlyphs = NSRange()
                let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphs)
                let offset = layoutManager.characterIndexForGlyph(at: glyphIndex)
                let line = Self.lineNumber(atOffset: offset, lineStarts: lineStarts)
                if lineStarts[line - 1] == offset {
                    drawNumber(line, below: lineRect)
                }
                glyphIndex = max(NSMaxRange(lineGlyphs), glyphIndex + 1)
            }
            if layoutManager.extraLineFragmentTextContainer != nil {
                drawNumber(lineStarts.count, below: layoutManager.extraLineFragmentRect)
            }
        }
    }

    #Preview("Line numbers") {
        CodeEditorView(
            kind: "md",
            text: .constant(
                "# Meeting Notes\n\n## Kickoff\n- Agenda for the launch\n- Website copy due Friday\n\n## Done\n- Roadmap review"
            ),
            isEditable: false
        )
        .frame(width: 480, height: 320)
        .background(Color.macCard)
    }
#endif
