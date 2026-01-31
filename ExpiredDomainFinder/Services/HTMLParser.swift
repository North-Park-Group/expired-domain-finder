import Foundation
import SwiftSoup

enum HTMLParser {
    private static let skipPrefixes = ["#", "mailto:", "tel:", "javascript:", "data:"]
    private static let inlineURLPattern = try! NSRegularExpression(
        pattern: #"https?://[^\s"'<>\\\)}\]]+"#
    )
    private static let dataURLAttributes = ["data-href", "data-url", "data-src", "data-link", "data-page", "data-target"]

    struct ExtractedURLs {
        let crawlURLs: [String]
        let anchorURLs: [String]
        let paginationURLs: [String]
        let iframeURLs: [String]
    }

    static func extractURLs(html: String, baseURL: String) -> ExtractedURLs {
        var crawlURLs: [String] = []
        var anchorURLs: [String] = []
        var paginationURLs: [String] = []
        var iframeURLs: [String] = []

        // Determine effective base URL (handle <base href>)
        let effectiveBase: String
        if let doc = try? SwiftSoup.parse(html, baseURL),
           let baseElement = try? doc.select("base[href]").first(),
           let baseHref = try? baseElement.attr("abs:href"),
           !baseHref.isEmpty {
            effectiveBase = baseHref
        } else {
            effectiveBase = baseURL
        }

        guard let doc = try? SwiftSoup.parse(html, effectiveBase) else {
            return ExtractedURLs(crawlURLs: [], anchorURLs: [], paginationURLs: [], iframeURLs: [])
        }

        // 1. <a href> and <link href>
        let tagAttrs: [(String, String)] = [("a", "href"), ("link", "href")]
        for (tag, attr) in tagAttrs {
            guard let elements = try? doc.select("\(tag)[\(attr)]") else { continue }
            for element in elements {
                guard let raw = try? element.attr("abs:\(attr)"),
                      !raw.isEmpty,
                      !skipPrefixes.contains(where: { raw.hasPrefix($0) }) else { continue }
                crawlURLs.append(raw)
                if tag == "a" { anchorURLs.append(raw) }

                // 3. rel="next" / rel="prev" pagination
                if tag == "link" || tag == "a" {
                    let rel = (try? element.attr("rel"))?.lowercased() ?? ""
                    if rel == "next" || rel == "prev" {
                        paginationURLs.append(raw)
                    }
                }
            }
        }

        // 4. <iframe src>
        if let iframes = try? doc.select("iframe[src]") {
            for iframe in iframes {
                guard let src = try? iframe.attr("abs:src"),
                      !src.isEmpty,
                      !skipPrefixes.contains(where: { src.hasPrefix($0) }) else { continue }
                iframeURLs.append(src)
                crawlURLs.append(src)
            }
        }

        // 2. data-* attributes with URL values
        for dataAttr in dataURLAttributes {
            if let elements = try? doc.select("[\(dataAttr)]") {
                for element in elements {
                    guard let raw = try? element.attr(dataAttr),
                          !raw.isEmpty else { continue }

                    // Resolve relative URLs
                    let resolved: String
                    if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
                        resolved = raw
                    } else if raw.hasPrefix("/") {
                        // Absolute path — resolve against base
                        if let baseComps = URLComponents(string: effectiveBase),
                           let scheme = baseComps.scheme, let host = baseComps.host {
                            resolved = "\(scheme)://\(host)\(raw)"
                        } else {
                            continue
                        }
                    } else {
                        continue
                    }

                    guard !skipPrefixes.contains(where: { resolved.hasPrefix($0) }) else { continue }
                    crawlURLs.append(resolved)
                    anchorURLs.append(resolved)
                }
            }
        }

        // 1. Scan ALL <script> blocks for URLs (not just data scripts)
        if let scripts = try? doc.select("script") {
            for script in scripts {
                guard let rawText = try? script.html(), rawText.count >= 20 else { continue }

                // Skip external script tags with no inline content
                let src = (try? script.attr("src")) ?? ""
                if !src.isEmpty && rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }

                // Pre-unescape JS forward slashes so regex can match URLs like https:\/\/
                let text = rawText.replacingOccurrences(of: "\\/", with: "/")

                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                let matches = inlineURLPattern.matches(in: text, range: range)
                for match in matches {
                    guard let r = Range(match.range, in: text) else { continue }
                    var url = String(text[r])
                    // Strip trailing punctuation
                    while let last = url.last, [",", ";", ":", ".", "'", "\"", ")"].contains(String(last)) {
                        url.removeLast()
                    }
                    // Already unescaped above

                    if url.hasPrefix("http://") || url.hasPrefix("https://") {
                        // Skip obvious non-page resources
                        let lower = url.lowercased()
                        let skipExtensions = [".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".ico",
                                              ".css", ".woff", ".woff2", ".ttf", ".eot",
                                              ".mp4", ".mp3", ".webm", ".ogg"]
                        if skipExtensions.contains(where: { lower.hasSuffix($0) }) { continue }

                        crawlURLs.append(url)
                        anchorURLs.append(url)
                    }
                }
            }
        }

        // Scan HTML comments for URLs
        // SwiftSoup doesn't directly expose comments, so we use regex on raw HTML
        let commentPattern = try! NSRegularExpression(pattern: #"<!--([\s\S]*?)-->"#)
        let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let commentMatches = commentPattern.matches(in: html, range: htmlRange)
        for match in commentMatches {
            guard let contentRange = Range(match.range(at: 1), in: html) else { continue }
            let commentText = String(html[contentRange])
            let cRange = NSRange(commentText.startIndex..<commentText.endIndex, in: commentText)
            let urlMatches = inlineURLPattern.matches(in: commentText, range: cRange)
            for urlMatch in urlMatches {
                guard let r = Range(urlMatch.range, in: commentText) else { continue }
                var url = String(commentText[r])
                while let last = url.last, [",", ";", ":", "."].contains(String(last)) {
                    url.removeLast()
                }
                if url.hasPrefix("http://") || url.hasPrefix("https://") {
                    crawlURLs.append(url)
                }
            }
        }

        return ExtractedURLs(crawlURLs: crawlURLs, anchorURLs: anchorURLs,
                             paginationURLs: paginationURLs, iframeURLs: iframeURLs)
    }
}
