import Foundation

enum URLPriority {
    // Content pages: highest priority (lowest number)
    private static let contentPattern = try! NSRegularExpression(
        pattern: #"/(?:thread|topic|post|article|blog|entry|discussion|comment|review|viewtopic|showthread|showpost|viewthread|p/|t/)"#,
        options: .caseInsensitive
    )

    // Index/nav pages: lowest priority (highest number)
    private static let indexPattern = try! NSRegularExpression(
        pattern: #"/(?:forum|category|categories|tag|tags|page|index|archive|members|users|online|login|register|account|search|wiki|feeds|whats-new|latest-activity|media|help)"#,
        options: .caseInsensitive
    )

    static func priority(for url: String, depth: Int) -> Int {
        guard let components = URLComponents(string: url) else { return 50 + depth }
        let path = components.path
        let range = NSRange(path.startIndex..<path.endIndex, in: path)

        if contentPattern.firstMatch(in: path, range: range) != nil {
            return depth
        }
        if indexPattern.firstMatch(in: path, range: range) != nil {
            return 100 + depth
        }
        return 50 + depth
    }

    /// Pagination links get high priority — they lead to more content pages
    static func paginationPriority(depth: Int) -> Int {
        return max(0, depth - 1)
    }
}
