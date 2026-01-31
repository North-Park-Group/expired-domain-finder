import Foundation

enum RobotsTxtSeeder {
    static func fetchSitemapURLs(baseURL: String, client: NetworkClient) async -> Set<String> {
        guard let parsed = URLComponents(string: baseURL),
              let host = parsed.host else { return [] }
        let robotsURL = "\(parsed.scheme ?? "https")://\(host)/robots.txt"
        guard let url = URL(string: robotsURL) else { return [] }

        var sitemaps: Set<String> = []
        guard let (text, response) = try? await client.fetchString(url: url, timeout: 10),
              (200..<300).contains(response.statusCode) else { return [] }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("sitemap:") {
                let value = trimmed.dropFirst("sitemap:".count).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { sitemaps.insert(value) }
            }
        }
        return sitemaps
    }
}
