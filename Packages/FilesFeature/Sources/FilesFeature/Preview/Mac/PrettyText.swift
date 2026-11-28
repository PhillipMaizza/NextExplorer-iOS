#if os(macOS)
    import Foundation

    enum PrettyText {
        private enum Format {
            case json
            case xml

            init?(kind: String) {
                switch kind.lowercased() {
                case "json": self = .json
                case "xml", "plist": self = .xml
                default: return nil
                }
            }
        }

        private static let indent = "  "
        private static let crampedLineGrowth = 2

        static func format(_ text: String, kind: String) -> String? {
            guard let format = Format(kind: kind) else { return nil }
            let formatted = switch format {
            case .json: json(text)
            case .xml: xml(text)
            }
            guard let formatted, lineCount(formatted) > lineCount(text) * crampedLineGrowth else { return nil }
            return formatted
        }

        private static func lineCount(_ text: String) -> Int {
            text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").count
        }

        private static func json(_ text: String) -> String? {
            guard let data = text.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil
            else { return nil }
            var output = ""
            var depth = 0
            var isInString = false
            var isEscaped = false
            var pendingOpen: Character?

            func newline() {
                output += "\n" + String(repeating: indent, count: depth)
            }

            for character in text {
                if !isInString, character.isWhitespace {
                    continue
                }
                if let open = pendingOpen {
                    pendingOpen = nil
                    if (character == "}" && open == "{") || (character == "]" && open == "[") {
                        output.append(character)
                        depth -= 1
                        continue
                    }
                    newline()
                }
                if isInString {
                    output.append(character)
                    if isEscaped {
                        isEscaped = false
                    } else if character == "\\" {
                        isEscaped = true
                    } else if character == "\"" {
                        isInString = false
                    }
                    continue
                }
                switch character {
                case "\"":
                    isInString = true
                    output.append(character)
                case "{", "[":
                    output.append(character)
                    depth += 1
                    pendingOpen = character
                case "}", "]":
                    depth -= 1
                    newline()
                    output.append(character)
                case ",":
                    output.append(character)
                    newline()
                case ":":
                    output += ": "
                default:
                    output.append(character)
                }
            }
            return output
        }

        private static func xml(_ text: String) -> String? {
            guard let document = try? XMLDocument(xmlString: text, options: []),
                  let root = document.rootElement() else { return nil }
            let body = root.xmlString(options: [.nodePrettyPrint])
            let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard source.hasPrefix("<?xml"), let end = source.range(of: "?>") else { return body }
            return source[..<end.upperBound] + "\n" + body
        }
    }
#endif
