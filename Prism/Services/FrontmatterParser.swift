import Foundation

enum FrontmatterParser {

    struct ParsedDocument {
        var frontmatter: [String: Any]
        var content: String
        var tags: [String]
    }

    static func parse(_ text: String) -> ParsedDocument {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("---") else {
            return ParsedDocument(frontmatter: [:], content: text, tags: [])
        }

        // Find the closing ---
        let lines = text.components(separatedBy: "\n")
        var closingIndex: Int?

        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                closingIndex = i
                break
            }
        }

        guard let endIndex = closingIndex else {
            return ParsedDocument(frontmatter: [:], content: text, tags: [])
        }

        let yamlLines = lines[1..<endIndex]
        let yamlString = yamlLines.joined(separator: "\n")
        let frontmatter = parseYAML(yamlString)

        // Content is everything after the closing ---
        let contentLines = lines[(endIndex + 1)...]
        let content = contentLines.joined(separator: "\n")
        // Strip at most one leading newline from content after frontmatter
        let trimmedContent = content.hasPrefix("\n") ? String(content.dropFirst()) : content

        let tags = extractTags(from: frontmatter)

        return ParsedDocument(frontmatter: frontmatter, content: trimmedContent, tags: tags)
    }

    static func serialize(content: String, tags: [String]) -> String {
        if tags.isEmpty {
            return content
        }

        let tagList = tags.map { $0 }.joined(separator: ", ")
        return """
        ---
        tags: [\(tagList)]
        ---
        \(content)
        """
    }

    // Minimal YAML parser — handles `tags: [a, b, c]` and `key: value`
    private static func parseYAML(_ yaml: String) -> [String: Any] {
        var result: [String: Any] = [:]

        for line in yaml.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }

            let key = String(trimmed[trimmed.startIndex..<colonIndex])
                .trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)

            // Check if value is an array like [a, b, c]
            if rawValue.hasPrefix("[") && rawValue.hasSuffix("]") {
                let inner = String(rawValue.dropFirst().dropLast())
                let items = inner
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                result[key] = items
            } else {
                result[key] = rawValue
            }
        }

        return result
    }

    private static func extractTags(from frontmatter: [String: Any]) -> [String] {
        if let tags = frontmatter["tags"] as? [String] {
            return tags
        }
        return []
    }
}
