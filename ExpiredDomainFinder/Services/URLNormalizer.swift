import Foundation

enum URLNormalizer {
    private static let contentParams: Set<String> = [
        "id", "p", "page", "topic", "thread", "post", "article", "view",
        "pid", "tid", "sid", "fid", "showtopic", "showpost", "t", "f",
    ]

    static func normalize(_ urlString: String) -> String? {
        guard var components = URLComponents(string: urlString) else { return nil }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil

        // Strip trailing slashes from path
        var path = components.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        if path.isEmpty { path = "/" }
        components.path = path

        // Filter query params
        if let queryItems = components.queryItems, !queryItems.isEmpty {
            let kept = queryItems
                .filter { contentParams.contains($0.name.lowercased()) }
                .sorted { $0.name < $1.name }
            components.queryItems = kept.isEmpty ? nil : kept
        } else {
            components.queryItems = nil
        }

        return components.string
    }
}
