import Foundation
import SwiftSoup

enum RSSSeeder {
    static func fetchURLs(baseURL: String, client: NetworkClient) async -> Set<String> {
        guard let parsed = URLComponents(string: baseURL) else { return [] }
        let baseDomain = (parsed.host ?? "").lowercased()
        let origin = "\(parsed.scheme ?? "https")://\(parsed.host ?? "")"

        var discovered: Set<String> = []
        var feedURLs: Set<String> = []

        // Common feed paths
        for path in ["/feed", "/rss", "/feed/rss", "/rss.xml", "/atom.xml", "/feed.xml", "/feeds"] {
            feedURLs.insert("\(origin)\(path)")
        }

        // Check homepage for <link rel="alternate"> feeds
        if let homeURL = URL(string: baseURL) {
            if let (html, resp) = try? await client.fetchString(url: homeURL, timeout: 15),
               (200..<300).contains(resp.statusCode) {
                if let doc = try? SwiftSoup.parse(html, baseURL) {
                    if let links = try? doc.select("link[rel=alternate]") {
                        for link in links {
                            let type = (try? link.attr("type")) ?? ""
                            if type.contains("rss") || type.contains("atom") || type.contains("xml") {
                                if let href = try? link.attr("abs:href"), !href.isEmpty {
                                    feedURLs.insert(href)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Parse feeds (two passes for discovery)
        var parsed2: Set<String> = []
        for _ in 0..<2 {
            let remaining = feedURLs.subtracting(parsed2)
            for feedURL in remaining {
                parsed2.insert(feedURL)
                await parseFeed(urlString: feedURL, baseDomain: baseDomain, origin: origin,
                                client: client, discovered: &discovered, feedURLs: &feedURLs)
            }
        }

        return discovered
    }

    private static func parseFeed(
        urlString: String, baseDomain: String, origin: String,
        client: NetworkClient,
        discovered: inout Set<String>, feedURLs: inout Set<String>
    ) async {
        guard let url = URL(string: urlString) else { return }
        guard let (text, response) = try? await client.fetchString(url: url, timeout: 15),
              (200..<300).contains(response.statusCode) else { return }

        let ct = response.value(forHTTPHeaderField: "Content-Type") ?? ""

        // HTML page listing feeds
        if ct.contains("text/html") {
            let pattern = try! NSRegularExpression(
                pattern: "href=[\"'](\(NSRegularExpression.escapedPattern(for: origin))/feeds/[^\"']+)[\"']"
            )
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in pattern.matches(in: text, range: range) {
                if let r = Range(match.range(at: 1), in: text) {
                    feedURLs.insert(String(text[r]))
                }
            }
            return
        }

        // Parse XML feed
        let cleaned = text.replacingOccurrences(
            of: #"\s+xmlns\s*=\s*"[^"]*""#, with: "", options: .regularExpression
        )
        guard let data = cleaned.data(using: .utf8) else { return }

        let feedParser = FeedXMLParser(baseDomain: baseDomain)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = feedParser
        xmlParser.parse()

        for loc in feedParser.urls {
            if let norm = URLNormalizer.normalize(loc) {
                discovered.insert(norm)
            }
        }
    }
}

private final class FeedXMLParser: NSObject, XMLParserDelegate {
    let baseDomain: String
    var urls: [String] = []

    private var currentElement = ""
    private var currentText = ""
    private var inItem = false
    private var inEntry = false

    init(baseDomain: String) { self.baseDomain = baseDomain }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        let local = element.lowercased()
        currentElement = local
        currentText = ""

        if local == "item" { inItem = true }
        else if local == "entry" { inEntry = true }
        else if local == "link" && inEntry {
            // Atom <link href="">
            if let href = attributes["href"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !href.isEmpty {
                let domain = URLComponents(string: href)?.host?.lowercased() ?? ""
                if domain == baseDomain || domain.hasSuffix("." + baseDomain) {
                    urls.append(href)
                }
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "link" && inItem { currentText += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        let local = element.lowercased()
        if local == "link" && inItem {
            let link = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !link.isEmpty {
                let domain = URLComponents(string: link)?.host?.lowercased() ?? ""
                if domain == baseDomain || domain.hasSuffix("." + baseDomain) {
                    urls.append(link)
                }
            }
        }
        if local == "item" { inItem = false }
        if local == "entry" { inEntry = false }
        currentElement = ""
    }
}
