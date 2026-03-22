import Foundation

struct BookmarkMeta {
    var title: String?
    var description: String?
    var imageURL: String?
    var faviconURL: String?
    var siteName: String?
}

enum BookmarkMetaFetcher {

    static func fetch(urlString: String, completion: @escaping (BookmarkMeta) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(BookmarkMeta())
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("[BM] Fetch error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(fallbackMeta(for: url)) }
                return
            }

            // Only parse text/html responses
            if let httpResponse = response as? HTTPURLResponse,
               let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
               !contentType.contains("text/html") && !contentType.contains("text/xhtml") {
                print("[BM] Non-HTML response: \(contentType)")
                DispatchQueue.main.async { completion(fallbackMeta(for: url)) }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async { completion(fallbackMeta(for: url)) }
                return
            }

            // Limit to first 50KB (only need <head> section)
            let limitedData = data.prefix(50_000)
            guard let html = String(data: limitedData, encoding: .utf8)
                    ?? String(data: limitedData, encoding: .ascii) else {
                DispatchQueue.main.async { completion(fallbackMeta(for: url)) }
                return
            }

            let meta = parseHTML(html, baseURL: url)
            DispatchQueue.main.async { completion(meta) }
        }.resume()
    }

    // MARK: - HTML Parsing

    private static func parseHTML(_ html: String, baseURL: URL) -> BookmarkMeta {
        var meta = BookmarkMeta()

        // og:title → <title>
        meta.title = extractMetaContent(html, property: "og:title")
            ?? extractTitleTag(html)

        // og:description → <meta name="description">
        meta.description = extractMetaContent(html, property: "og:description")
            ?? extractMetaContent(html, name: "description")

        // og:image
        if let image = extractMetaContent(html, property: "og:image") {
            meta.imageURL = resolveURL(image, base: baseURL)
        }

        // og:site_name → domain
        meta.siteName = extractMetaContent(html, property: "og:site_name")
            ?? baseURL.host?.replacingOccurrences(of: "www.", with: "")

        // Favicon: <link rel="icon"> → /favicon.ico fallback
        if let favicon = extractFaviconHref(html) {
            meta.faviconURL = resolveURL(favicon, base: baseURL)
        } else if let scheme = baseURL.scheme, let host = baseURL.host {
            meta.faviconURL = "\(scheme)://\(host)/favicon.ico"
        }

        return meta
    }

    // MARK: - Meta Tag Extraction

    /// Extract content from `<meta property="X" content="Y">` or `<meta content="Y" property="X">`
    private static func extractMetaContent(_ html: String, property: String) -> String? {
        // Pattern 1: property before content
        let p1 = try? NSRegularExpression(
            pattern: #"<meta[^>]+property\s*=\s*["']"# + NSRegularExpression.escapedPattern(for: property) + #"["'][^>]+content\s*=\s*["']([^"']+)["']"#,
            options: .caseInsensitive
        )
        if let match = p1?.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Pattern 2: content before property
        let p2 = try? NSRegularExpression(
            pattern: #"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+property\s*=\s*["']"# + NSRegularExpression.escapedPattern(for: property) + #"["']"#,
            options: .caseInsensitive
        )
        if let match = p2?.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    /// Extract content from `<meta name="X" content="Y">`
    private static func extractMetaContent(_ html: String, name: String) -> String? {
        let p1 = try? NSRegularExpression(
            pattern: #"<meta[^>]+name\s*=\s*["']"# + NSRegularExpression.escapedPattern(for: name) + #"["'][^>]+content\s*=\s*["']([^"']+)["']"#,
            options: .caseInsensitive
        )
        if let match = p1?.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let p2 = try? NSRegularExpression(
            pattern: #"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+name\s*=\s*["']"# + NSRegularExpression.escapedPattern(for: name) + #"["']"#,
            options: .caseInsensitive
        )
        if let match = p2?.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    /// Extract <title>...</title>
    private static func extractTitleTag(_ html: String) -> String? {
        let pattern = try? NSRegularExpression(
            pattern: #"<title[^>]*>([^<]+)</title>"#,
            options: .caseInsensitive
        )
        if let match = pattern?.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            let title = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }
        return nil
    }

    /// Extract href from `<link rel="icon" href="...">` or `<link rel="shortcut icon" href="...">`
    private static func extractFaviconHref(_ html: String) -> String? {
        let pattern = try? NSRegularExpression(
            pattern: #"<link[^>]+rel\s*=\s*["'](?:shortcut )?icon["'][^>]+href\s*=\s*["']([^"']+)["']"#,
            options: .caseInsensitive
        )
        if let match = pattern?.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Also check href before rel
        let p2 = try? NSRegularExpression(
            pattern: #"<link[^>]+href\s*=\s*["']([^"']+)["'][^>]+rel\s*=\s*["'](?:shortcut )?icon["']"#,
            options: .caseInsensitive
        )
        if let match = p2?.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    // MARK: - Helpers

    private static func resolveURL(_ href: String, base: URL) -> String {
        if href.hasPrefix("http://") || href.hasPrefix("https://") || href.hasPrefix("data:") {
            return href
        }
        if href.hasPrefix("//") {
            return (base.scheme ?? "https") + ":" + href
        }
        if let resolved = URL(string: href, relativeTo: base)?.absoluteString {
            return resolved
        }
        return href
    }

    private static func fallbackMeta(for url: URL) -> BookmarkMeta {
        BookmarkMeta(
            title: nil,
            description: nil,
            imageURL: nil,
            faviconURL: url.scheme.map { "\($0)://\(url.host ?? "")/favicon.ico" },
            siteName: url.host?.replacingOccurrences(of: "www.", with: "")
        )
    }
}
