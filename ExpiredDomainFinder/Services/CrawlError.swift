import Foundation

/// Structured error types for the crawl pipeline.
enum CrawlError: Error, CustomStringConvertible {
    case networkFailure(url: String, underlying: Error)
    case nonHTMLContent(url: String, contentType: String)
    case httpError(url: String, statusCode: Int)
    case parseFailure(url: String)
    case timeout(url: String)
    case invalidURL(String)

    var description: String {
        switch self {
        case .networkFailure(let url, let err):
            return "Network failure for \(url): \(err.localizedDescription)"
        case .nonHTMLContent(let url, let ct):
            return "Non-HTML content at \(url): \(ct)"
        case .httpError(let url, let code):
            return "HTTP \(code) for \(url)"
        case .parseFailure(let url):
            return "Parse failure for \(url)"
        case .timeout(let url):
            return "Timeout for \(url)"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        }
    }
}
