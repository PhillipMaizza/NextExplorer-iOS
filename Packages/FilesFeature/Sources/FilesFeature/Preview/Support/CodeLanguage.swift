enum CodeLanguage: CaseIterable {
    case json, javaScript, typeScript, tsx, html, css, scss, python, ruby, php, go, rust, java, c, cpp
    case cSharp, sql, yaml, toml, markdown, bash, swift

    init?(kind: String) {
        switch kind.lowercased() {
        case "json": self = .json
        case "js", "jsx": self = .javaScript
        case "ts": self = .typeScript
        case "tsx": self = .tsx
        case "html", "htm": self = .html
        case "css": self = .css
        case "scss": self = .scss
        case "py": self = .python
        case "rb": self = .ruby
        case "php": self = .php
        case "go": self = .go
        case "rs": self = .rust
        case "java": self = .java
        case "c": self = .c
        case "cpp", "cc", "cxx": self = .cpp
        case "cs": self = .cSharp
        case "sql": self = .sql
        case "yml", "yaml": self = .yaml
        case "toml": self = .toml
        case "md", "markdown": self = .markdown
        case "sh", "bash", "zsh": self = .bash
        case "swift": self = .swift
        default: return nil
        }
    }
}
