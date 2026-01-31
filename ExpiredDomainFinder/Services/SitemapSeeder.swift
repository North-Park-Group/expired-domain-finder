import Foundation

enum SitemapSeeder {
    static func fetchURLs(
        baseURL: String,
        extraSitemapURLs: Set<String> = [],
        client: NetworkClient
    ) async -> Set<String> {
        guard let parsed = URLComponents(string: baseURL) else { return [] }
        let baseDomain = (parsed.host ?? "").lowercased()
        let origin = "\(parsed.scheme ?? "https")://\(parsed.host ?? "")"

        var sitemapURLs = [
            "\(origin)/sitemap.xml",
            "\(origin)/sitemap_index.xml",
            "\(origin)/sitemap-index.xml",
        ]
        sitemapURLs.append(contentsOf: extraSitemapURLs)

        var discovered: Set<String> = []
        var visited: Set<String> = []

        for sitemapURL in sitemapURLs {
            await parseSitemap(urlString: sitemapURL, baseDomain: baseDomain, client: client,
                               discovered: &discovered, visited: &visited)
        }

        return discovered
    }

    private static func parseSitemap(
        urlString: String,
        baseDomain: String,
        client: NetworkClient,
        discovered: inout Set<String>,
        visited: inout Set<String>
    ) async {
        guard !visited.contains(urlString), let url = URL(string: urlString) else { return }
        visited.insert(urlString)

        guard let (text, response) = try? await client.fetchString(url: url, timeout: 15),
              (200..<300).contains(response.statusCode) else { return }

        // Strip XML namespace for easier parsing
        let cleaned = text.replacingOccurrences(
            of: #"\s+xmlns\s*=\s*"[^"]*""#, with: "", options: .regularExpression,
            range: text.range(of: text) // only first occurrence-ish
        )

        guard let data = cleaned.data(using: .utf8) else { return }

        let parser = SitemapXMLParser(baseDomain: baseDomain)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()

        for loc in parser.sitemapLocs {
            await parseSitemap(urlString: loc, baseDomain: baseDomain, client: client,
                               discovered: &discovered, visited: &visited)
        }

        for loc in parser.urlLocs {
            guard let comp = URLComponents(string: loc) else { continue }
            let domain = (comp.host ?? "").lowercased()
            if domain == baseDomain || domain.hasSuffix("." + baseDomain) {
                if let norm = URLNormalizer.normalize(loc) {
                    discovered.insert(norm)
                }
            }
        }
    }
}

private final class SitemapXMLParser: NSObject, XMLParserDelegate {
    let baseDomain: String
    var sitemapLocs: [String] = []
    var urlLocs: [String] = []

    private var currentElement = ""
    private var currentText = ""
    private var inSitemap = false
    private var inURL = false

    init(baseDomain: String) { self.baseDomain = baseDomain }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        let local = element.lowercased()
        if local == "sitemap" { inSitemap = true }
        else if local == "url" { inURL = true }
        else if local == "loc" { currentText = "" }
        currentElement = local
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "loc" { currentText += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        let local = element.lowercased()
        if local == "loc" {
            let loc = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !loc.isEmpty {
                if inSitemap { sitemapLocs.append(loc) }
                else if inURL { urlLocs.append(loc) }
            }
        }
        if local == "sitemap" { inSitemap = false }
        if local == "url" { inURL = false }
        currentElement = ""
    }
}
