import CoreModels
import Foundation

/// The first lines of a text or code file, shaped for a thumbnail the size of a file icon.
enum TextSnippet {
    private enum Constants {
        /// How much of the file is looked at; a thumbnail shows a few lines, so the rest is never read.
        static let sampleBytes = 4096
        static let maxLines = 12
        static let maxColumns = 40
        /// Tabs are drawn as this many spaces, so indentation stays narrow.
        static let tabSpaces = "  "
        static let replacementCharacter: Character = "\u{FFFD}"
        /// More than this share of undecodable characters says the bytes are not text.
        static let maxReplacementShare = 0.1
    }

    /// Whether files of this kind (their extension) are drawn from their own first lines: the text and
    /// code files the app can open in its editor, in place of an icon the server has no thumbnail for.
    static func isTextKind(_ kind: String) -> Bool {
        PreviewKind(FileItem(name: "file", path: "", dateModified: .distantPast, size: 0, kind: kind)) == .text
    }

    /// The first lines of `data`, or `nil` when the bytes are not text (a NUL byte, mostly undecodable) or hold
    /// nothing visible.
    static func make(from data: Data) -> String? {
        let sample = data.prefix(Constants.sampleBytes)
        guard !sample.contains(0) else { return nil }
        var characters = Array(String(decoding: sample, as: UTF8.self))
        // The sample may end inside a character, which decodes to a replacement character.
        if data.count > Constants.sampleBytes, characters.last == Constants.replacementCharacter {
            characters.removeLast()
        }
        let broken = characters.count { $0 == Constants.replacementCharacter }
        guard !characters.isEmpty, Double(broken) / Double(characters.count) <= Constants.maxReplacementShare else {
            return nil
        }
        var lines = String(characters)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: Constants.tabSpaces)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0.prefix(Constants.maxColumns)) }
        while lines.first?.allSatisfy(\.isWhitespace) == true {
            lines.removeFirst()
        }
        lines = Array(lines.prefix(Constants.maxLines))
        while lines.last?.allSatisfy(\.isWhitespace) == true {
            lines.removeLast()
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
