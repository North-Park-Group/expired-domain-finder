import Testing
@testable import ExpiredDomainFinder

@Suite("HTMLParser Link Discovery")
struct HTMLParserTests {

    // MARK: - 1. Script block URL extraction

    @Test("Extracts URLs from all script blocks, not just data scripts")
    func scriptBlockURLs() {
        let html = """
        <html><head></head><body>
        <script>
            var config = {
                apiUrl: "https://api.example.com/v1/data",
                shareUrl: "https://share.external.com/page"
            };
        </script>
        </body></html>
        """
        let result = HTMLParser.extractURLs(html: html, baseURL: "https://example.com")
        #expect(result.crawlURLs.contains("https://api.example.com/v1/data"))
        #expect(result.anchorURLs.contains("https://share.external.com/page"))
    }

    @Test("Unescapes JS forward slashes in script URLs")
    func jsEscapedSlashes() {
        // In real JSON payloads, \/ appears as a literal backslash + forward slash
        let html = "<html><body><script>window.__data = {\"url\":\"https:\\/\\/example.com\\/blog\\/post-1\"};</script></body></html>"
            .replacingOccurrences(of: "\\\\", with: "\\") // doesn't apply here — already literal
        // Build the HTML with actual backslash-escaped slashes as they appear in real JS
        let realHTML = #"<html><body><script>window.__data = {"url":"https:\/\/example.com\/blog\/post-1"};</script></body></html>"#
        let result = HTMLParser.extractURLs(html: realHTML, baseURL: "https://example.com")
        #expect(result.crawlURLs.contains("https://example.com/blog/post-1"))
    }

    @Test("Skips image/font/media URLs from scripts")
    func skipsAssetURLs() {
        let html = """
        <html><body>
        <script>
            var assets = {
                logo: "https://cdn.example.com/logo.png",
                font: "https://cdn.example.com/font.woff2",
                page: "https://example.com/about"
            };
        </script>
        </body></html>
        """
        let result = HTMLParser.extractURLs(html: html, baseURL: "https://example.com")
        #expect(!result.crawlURLs.contains("https://cdn.example.com/logo.png"))
        #expect(!result.crawlURLs.contains("https://cdn.example.com/font.woff2"))
        #expect(result.crawlURLs.contains("https://example.com/about"))
    }

    // MARK: - 2. data-* attribute extraction

    @Test("Extracts URLs from data-href attributes")
    func dataHrefAttributes() {
        let html = """
        <html><body>
        <div data-href="https://example.com/hidden-page">Click</div>
        <div data-url="/relative-page">More</div>
        </body></html>
        """
        let result = HTMLParser.extractURLs(html: html, baseURL: "https://example.com")
        #expect(result.crawlURLs.contains("https://example.com/hidden-page"))
        #expect(result.crawlURLs.contains("https://example.com/relative-page"))
    }

    @Test("Extracts URLs from data-src and data-link")
    func dataSrcAndLink() {
        let html = """
        <html><body>
        <img data-src="https://example.com/lazy-page" />
        <a data-link="/another-page">Link</a>
        </body></html>
        """
        let result = HTMLParser.extractURLs(html: html, baseURL: "https://example.com")
        #expect(result.crawlURLs.contains("https://example.com/lazy-page"))
        #expect(result.crawlURLs.contains("https://example.com/another-page"))
    }

    // MARK: - 3. rel="next" / rel="prev" pagination

    @Test("Detects link rel=next pagination")
    func linkRelNext() {
        let html = """
        <html><head>
        <link rel="next" href="https://example.com/blog/page/2" />
        <link rel="prev" href="https://example.com/blog/page/0" />
        </head><body></body></html>
        """
        let result = HTMLParser.extractURLs(html: html, baseURL: "https://example.com/blog/page/1")
        #expect(result.paginationURLs.contains("https://example.com/blog/page/2"))
        #expect(result.paginationURLs.contains("https://example.com/blog/page/0"))
    }

    @Test("Detects a rel=next pagination")
    func aRelNext() {
        let html = """
        <html><body>
        <a rel="next" href="https://example.com/forum/page-2">Next</a>
        </body></html>
        """
        let result = HTMLParser.extractURLs(html: html, baseURL: "https://example.com/forum/page-1")
        #expect(result.paginationURLs.contains("https://example.com/forum/page-2"))
    }

    // MARK: - 4. iframe src

    @Test("Extracts iframe src URLs")
    func iframeSrc() {
        let html = """
        <html><body>
        <iframe src="https://example.com/embedded-page"></iframe>
        <iframe src="https://external.com/widget"></iframe>
        </body></html>
        """
        let result = HTMLParser.extractURLs(html: html, baseURL: "https://example.com")
        #expect(result.iframeURLs.contains("https://example.com/embedded-page"))
        #expect(result.iframeURLs.contains("https://external.com/widget"))
        #expect(result.crawlURLs.contains("https://example.com/embedded-page"))
    }

    // MARK: - 5. <base href> handling

    @Test("Resolves relative URLs against base href")
    func baseHrefResolution() {
        let html = """
        <html><head>
        <base href="https://cdn.example.com/site/" />
        </head><body>
        <a href="page1.html">Page 1</a>
        <a href="/absolute-path">Absolute</a>
        </body></html>
        """
        let result = HTMLParser.extractURLs(html: html, baseURL: "https://example.com")
        // page1.html should resolve against the base href
        #expect(result.crawlURLs.contains("https://cdn.example.com/site/page1.html"))
        #expect(result.crawlURLs.contains("https://cdn.example.com/absolute-path"))
    }

    // MARK: - HTML comments

    @Test("Extracts URLs from HTML comments")
    func htmlCommentURLs() {
        let html = """
        <html><body>
        <!-- Old nav: https://example.com/old-section -->
        <!-- Staging: https://staging.example.com/test -->
        <a href="https://example.com/visible">Visible</a>
        </body></html>
        """
        let result = HTMLParser.extractURLs(html: html, baseURL: "https://example.com")
        #expect(result.crawlURLs.contains("https://example.com/old-section"))
        #expect(result.crawlURLs.contains("https://staging.example.com/test"))
    }

    // MARK: - Combined / integration

    @Test("Real-world SPA page with multiple link sources")
    func realWorldSPA() {
        let html = """
        <html>
        <head>
            <base href="https://myapp.com/" />
            <link rel="next" href="https://myapp.com/articles?page=2" />
        </head>
        <body>
            <a href="about">About</a>
            <div data-href="/products/widget">Widget</div>
            <iframe src="https://external-reviews.com/embed/123"></iframe>
            <script>
                const routes = [
                    "https://myapp.com/api/articles",
                    "https://partner.com/feed"
                ];
            </script>
            <!-- TODO: re-enable https://myapp.com/beta-feature -->
        </body>
        </html>
        """
        let result = HTMLParser.extractURLs(html: html, baseURL: "https://myapp.com/articles")

        // Standard <a> resolved against <base>
        #expect(result.crawlURLs.contains("https://myapp.com/about"))
        // data-href
        #expect(result.crawlURLs.contains("https://myapp.com/products/widget"))
        // iframe
        #expect(result.iframeURLs.contains("https://external-reviews.com/embed/123"))
        // Script URLs
        #expect(result.crawlURLs.contains("https://myapp.com/api/articles"))
        #expect(result.anchorURLs.contains("https://partner.com/feed"))
        // Pagination
        #expect(result.paginationURLs.contains("https://myapp.com/articles?page=2"))
        // Comment
        #expect(result.crawlURLs.contains("https://myapp.com/beta-feature"))
    }

    @Test("Empty and malformed HTML returns empty results")
    func emptyHTML() {
        let result = HTMLParser.extractURLs(html: "", baseURL: "https://example.com")
        #expect(result.crawlURLs.isEmpty)
        #expect(result.paginationURLs.isEmpty)
        #expect(result.iframeURLs.isEmpty)
    }
}
