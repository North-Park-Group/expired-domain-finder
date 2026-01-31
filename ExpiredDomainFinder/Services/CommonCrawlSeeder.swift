import Foundation

enum CommonCrawlSeeder {
    static func fetchURLs(baseDomain: String, client: NetworkClient) async -> Set<String> {
        guard let collURL = URL(string: "https://index.commoncrawl.org/collinfo.json"),
              let (collData, collResp) = try? await client.fetch(url: collURL, timeout: 15),
              (200..<300).contains(collResp.statusCode),
              let collections = try? JSONSerialization.jsonObject(with: collData) as? [[String: Any]]
        else { return [] }

        var urls: Set<String> = []

        // Query only 2 most recent crawls
        for coll in collections.prefix(2) {
            guard let collId = coll["id"] as? String else { continue }
            let apiURL = "https://index.commoncrawl.org/\(collId)-index?url=*.\(baseDomain)&output=json&limit=5000"
            guard let url = URL(string: apiURL),
                  let (text, resp) = try? await client.fetchString(url: url, timeout: 30),
                  (200..<300).contains(resp.statusCode) else { continue }

            for line in text.split(separator: "\n") {
                guard let lineData = line.data(using: .utf8),
                      let record = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let recordURL = record["url"] as? String,
                      let norm = URLNormalizer.normalize(recordURL)
                else { continue }
                urls.insert(norm)
            }
        }

        return urls
    }
}
