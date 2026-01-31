import Testing
@testable import ExpiredDomainFinder

@Suite("ContentDeduplicator")
struct ContentDeduplicatorTests {

    @Test("Detects duplicate content")
    func detectsDuplicate() async {
        let dedup = ContentDeduplicator()
        // Need content > 2048 chars for the hash window
        let prefix = String(repeating: "a", count: 2048)
        let body = String(repeating: "b", count: 4096)
        let html = prefix + body

        let first = await dedup.isDuplicate(html: html)
        #expect(!first)

        let second = await dedup.isDuplicate(html: html)
        #expect(second)
    }

    @Test("Different content is not duplicate")
    func differentContent() async {
        let dedup = ContentDeduplicator()
        let prefix = String(repeating: "a", count: 2048)
        let html1 = prefix + String(repeating: "b", count: 4096)
        let html2 = prefix + String(repeating: "c", count: 4096)

        let first = await dedup.isDuplicate(html: html1)
        #expect(!first)

        let second = await dedup.isDuplicate(html: html2)
        #expect(!second)
    }

    @Test("Evicts old entries when at capacity")
    func evictsOldEntries() async {
        let dedup = ContentDeduplicator(maxEntries: 2)
        let prefix = String(repeating: "a", count: 2048)

        let html1 = prefix + String(repeating: "1", count: 4096)
        let html2 = prefix + String(repeating: "2", count: 4096)
        let html3 = prefix + String(repeating: "3", count: 4096)

        _ = await dedup.isDuplicate(html: html1) // slot 1
        _ = await dedup.isDuplicate(html: html2) // slot 2
        _ = await dedup.isDuplicate(html: html3) // evicts html1

        // html1 should no longer be recognized as duplicate
        let recheck = await dedup.isDuplicate(html: html1)
        #expect(!recheck)
    }

    @Test("Reset clears all state")
    func resetClears() async {
        let dedup = ContentDeduplicator()
        let prefix = String(repeating: "a", count: 2048)
        let html = prefix + String(repeating: "b", count: 4096)

        _ = await dedup.isDuplicate(html: html)
        await dedup.reset()

        let after = await dedup.isDuplicate(html: html)
        #expect(!after)
    }
}
