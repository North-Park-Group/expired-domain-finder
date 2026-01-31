import Testing
@testable import ExpiredDomainFinder

@Suite("URLPriority")
struct URLPriorityTests {

    @Test("Content pages get lowest priority number")
    func contentPagesHighPriority() {
        let prio = URLPriority.priority(for: "https://forum.com/thread/12345", depth: 1)
        #expect(prio == 1) // depth only
    }

    @Test("Index pages get highest priority number")
    func indexPagesLowPriority() {
        let prio = URLPriority.priority(for: "https://forum.com/category/general", depth: 1)
        #expect(prio == 101) // 100 + depth
    }

    @Test("Neutral pages get middle priority")
    func neutralPages() {
        let prio = URLPriority.priority(for: "https://example.com/some-page", depth: 2)
        #expect(prio == 52) // 50 + depth
    }

    @Test("Pagination priority boosts depth")
    func paginationPriority() {
        let prio = URLPriority.paginationPriority(depth: 3)
        #expect(prio == 2) // max(0, depth - 1)
    }

    @Test("Pagination priority doesn't go negative")
    func paginationNonNegative() {
        let prio = URLPriority.paginationPriority(depth: 0)
        #expect(prio == 0)
    }
}
