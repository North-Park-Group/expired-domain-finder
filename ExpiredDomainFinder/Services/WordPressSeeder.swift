import Foundation

/// Detects WordPress sites and discovers URLs from WP-specific endpoints.
enum WordPressSeeder {

    /// Probes the site for WordPress indicators and extracts URLs from WP endpoints.
    static func fetchURLs(baseURL: String, client: NetworkClient) async -> Set<String> {
        guard let components = URLComponents(string: baseURL),
              let host = components.host?.lowercased() else { return [] }
        let origin = "\(components.scheme ?? "https")://\(host)"

        // Quick detection: check for wp-json header or wp-content in homepage
        guard await isWordPress(origin: origin, client: client) else { return [] }

        var discovered: Set<String> = []

        // Fetch from multiple WP endpoints concurrently
        await withTaskGroup(of: Set<String>.self) { group in
            group.addTask { await fetchWPJSON(origin: origin, host: host, client: client) }
            group.addTask { await fetchWPSitemap(origin: origin, host: host, client: client) }
            group.addTask { await fetchWPCategories(origin: origin, host: host, client: client) }
            group.addTask { await fetchWPTags(origin: origin, host: host, client: client) }

            for await urls in group {
                discovered.formUnion(urls)
            }
        }

        return discovered
    }

    // MARK: - Detection

    private static func isWordPress(origin: String, client: NetworkClient) async -> Bool {
        // Method 1: Check wp-json discovery endpoint
        if let url = URL(string: "\(origin)/wp-json/"),
           let (_, response) = try? await client.fetch(url: url, timeout: 8) {
            if (200..<300).contains(response.statusCode) { return true }
        }

        // Method 2: Check homepage for wp-content references
        if let url = URL(string: origin),
           let (html, response) = try? await client.fetchString(url: url, timeout: 8),
           (200..<300).contains(response.statusCode) {
            let lower = html.lowercased()
            if lower.contains("wp-content/") || lower.contains("wp-includes/") ||
               lower.contains("/wp-json/") || lower.contains("wordpress") {
                return true
            }
        }

        return false
    }

    // MARK: - WP REST API

    private static func fetchWPJSON(origin: String, host: String, client: NetworkClient) async -> Set<String> {
        var urls: Set<String> = []

        // Fetch posts (paginated, up to 5 pages)
        for page in 1...5 {
            guard let url = URL(string: "\(origin)/wp-json/wp/v2/posts?per_page=100&page=\(page)&_fields=link") else { break }
            guard let (data, response) = try? await client.fetch(url: url, timeout: 10),
                  (200..<300).contains(response.statusCode) else { break }

            guard let posts = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { break }
            if posts.isEmpty { break }

            for post in posts {
                if let link = post["link"] as? String,
                   let norm = URLNormalizer.normalize(link) {
                    urls.insert(norm)
                }
            }

            // Check X-WP-TotalPages header
            if let totalPages = response.value(forHTTPHeaderField: "X-WP-TotalPages"),
               let total = Int(totalPages), page >= total { break }
        }

        // Fetch pages
        if let url = URL(string: "\(origin)/wp-json/wp/v2/pages?per_page=100&_fields=link"),
           let (data, response) = try? await client.fetch(url: url, timeout: 10),
           (200..<300).contains(response.statusCode),
           let pages = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for page in pages {
                if let link = page["link"] as? String,
                   let norm = URLNormalizer.normalize(link) {
                    urls.insert(norm)
                }
            }
        }

        return urls
    }

    // MARK: - WP Sitemap

    private static func fetchWPSitemap(origin: String, host: String, client: NetworkClient) async -> Set<String> {
        // WordPress 5.5+ has built-in sitemaps at /wp-sitemap.xml
        guard let url = URL(string: "\(origin)/wp-sitemap.xml"),
              let (text, response) = try? await client.fetchString(url: url, timeout: 10),
              (200..<300).contains(response.statusCode) else { return [] }

        var urls: Set<String> = []

        // Extract <loc> URLs from the sitemap index
        let locPattern = try! NSRegularExpression(pattern: #"<loc>\s*(https?://[^<]+?)\s*</loc>"#)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = locPattern.matches(in: text, range: range)

        for match in matches {
            guard let r = Range(match.range(at: 1), in: text) else { continue }
            let loc = String(text[r])

            // If it's a sub-sitemap, fetch it too
            if loc.contains("wp-sitemap") && loc.hasSuffix(".xml") {
                guard let subURL = URL(string: loc),
                      let (subText, subResponse) = try? await client.fetchString(url: subURL, timeout: 10),
                      (200..<300).contains(subResponse.statusCode) else { continue }

                let subRange = NSRange(subText.startIndex..<subText.endIndex, in: subText)
                let subMatches = locPattern.matches(in: subText, range: subRange)
                for subMatch in subMatches {
                    guard let sr = Range(subMatch.range(at: 1), in: subText) else { continue }
                    let subLoc = String(subText[sr])
                    if let comp = URLComponents(string: subLoc),
                       let h = comp.host?.lowercased(),
                       (h == host || h.hasSuffix("." + host)),
                       let norm = URLNormalizer.normalize(subLoc) {
                        urls.insert(norm)
                    }
                }
            } else if let comp = URLComponents(string: loc),
                      let h = comp.host?.lowercased(),
                      (h == host || h.hasSuffix("." + host)),
                      let norm = URLNormalizer.normalize(loc) {
                urls.insert(norm)
            }
        }

        return urls
    }

    // MARK: - WP Categories (often contain link-rich archive pages)

    private static func fetchWPCategories(origin: String, host: String, client: NetworkClient) async -> Set<String> {
        guard let url = URL(string: "\(origin)/wp-json/wp/v2/categories?per_page=100&_fields=link"),
              let (data, response) = try? await client.fetch(url: url, timeout: 10),
              (200..<300).contains(response.statusCode),
              let categories = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        var urls: Set<String> = []
        for cat in categories {
            if let link = cat["link"] as? String,
               let norm = URLNormalizer.normalize(link) {
                urls.insert(norm)
            }
        }
        return urls
    }

    // MARK: - WP Tags

    private static func fetchWPTags(origin: String, host: String, client: NetworkClient) async -> Set<String> {
        guard let url = URL(string: "\(origin)/wp-json/wp/v2/tags?per_page=100&_fields=link"),
              let (data, response) = try? await client.fetch(url: url, timeout: 10),
              (200..<300).contains(response.statusCode),
              let tags = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        var urls: Set<String> = []
        for tag in tags {
            if let link = tag["link"] as? String,
               let norm = URLNormalizer.normalize(link) {
                urls.insert(norm)
            }
        }
        return urls
    }
}
