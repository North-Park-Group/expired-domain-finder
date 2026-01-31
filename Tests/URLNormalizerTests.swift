import Testing
@testable import ExpiredDomainFinder

@Suite("URLNormalizer")
struct URLNormalizerTests {

    @Test("Lowercases scheme and host")
    func lowercasesSchemeAndHost() {
        let result = URLNormalizer.normalize("HTTPS://EXAMPLE.COM/Path")
        #expect(result == "https://example.com/Path")
    }

    @Test("Strips fragment")
    func stripsFragment() {
        let result = URLNormalizer.normalize("https://example.com/page#section")
        #expect(result == "https://example.com/page")
    }

    @Test("Strips trailing slashes")
    func stripsTrailingSlashes() {
        let result = URLNormalizer.normalize("https://example.com/page/")
        #expect(result == "https://example.com/page")
    }

    @Test("Preserves root path slash")
    func preservesRootSlash() {
        let result = URLNormalizer.normalize("https://example.com/")
        #expect(result == "https://example.com/")
    }

    @Test("Filters non-content query params")
    func filtersQueryParams() {
        let result = URLNormalizer.normalize("https://example.com/search?utm_source=google&page=2&ref=abc")
        #expect(result == "https://example.com/search?page=2")
    }

    @Test("Removes query string when no content params")
    func removesEmptyQuery() {
        let result = URLNormalizer.normalize("https://example.com/page?utm_source=google&ref=abc")
        #expect(result == "https://example.com/page")
    }

    @Test("Sorts query params alphabetically")
    func sortsQueryParams() {
        let result = URLNormalizer.normalize("https://example.com/page?thread=1&id=5")
        #expect(result == "https://example.com/page?id=5&thread=1")
    }

    @Test("Returns nil for invalid URL")
    func invalidURL() {
        let result = URLNormalizer.normalize("not a url :::")
        #expect(result == nil)
    }
}
