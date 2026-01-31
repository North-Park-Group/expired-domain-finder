import Foundation

enum WaybackSeeder {
    static func fetchURLs(baseDomain: String, client: NetworkClient) async -> Set<String> {
        let cdxURL = "https://web.archive.org/cdx/search/cdx"
            + "?url=\(baseDomain)"
            + "&matchType=domain"
            + "&output=json"
            + "&fl=original,statuscode,mimetype"
            + "&filter=statuscode:200"
            + "&filter=mimetype:text/html"
            + "&collapse=urlkey"
            + "&limit=10000"

        guard let url = URL(string: cdxURL) else { return [] }
        guard let (data, response) = try? await client.fetch(url: url, timeout: 30),
              (200..<300).contains(response.statusCode) else { return [] }

        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String]],
              rows.count >= 2 else { return [] }

        var urls: Set<String> = []
        for row in rows.dropFirst() {
            guard let original = row.first,
                  let norm = URLNormalizer.normalize(original) else { continue }
            urls.insert(norm)
        }
        return urls
    }
}
