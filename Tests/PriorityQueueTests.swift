import Testing
@testable import ExpiredDomainFinder

@Suite("PriorityQueue")
struct PriorityQueueTests {

    @Test("Empty queue returns nil")
    func emptyQueue() {
        var q = PriorityQueue<Int>()
        #expect(q.isEmpty)
        #expect(q.removeMin() == nil)
    }

    @Test("Single element")
    func singleElement() {
        var q = PriorityQueue<Int>()
        q.insert(42)
        #expect(q.count == 1)
        #expect(q.removeMin() == 42)
        #expect(q.isEmpty)
    }

    @Test("Elements come out in sorted order")
    func sortedOrder() {
        var q = PriorityQueue<Int>()
        for v in [5, 3, 8, 1, 9, 2, 7] {
            q.insert(v)
        }
        var result: [Int] = []
        while let v = q.removeMin() {
            result.append(v)
        }
        #expect(result == [1, 2, 3, 5, 7, 8, 9])
    }

    @Test("Duplicate values handled correctly")
    func duplicates() {
        var q = PriorityQueue<Int>()
        q.insert(3)
        q.insert(1)
        q.insert(3)
        q.insert(1)
        var result: [Int] = []
        while let v = q.removeMin() {
            result.append(v)
        }
        #expect(result == [1, 1, 3, 3])
    }

    @Test("Min peek without removal")
    func minPeek() {
        var q = PriorityQueue<Int>()
        q.insert(5)
        q.insert(2)
        q.insert(8)
        #expect(q.min == 2)
        #expect(q.count == 3)
    }

    @Test("Large number of elements")
    func largeInsert() {
        var q = PriorityQueue<Int>()
        let values = (0..<1000).shuffled()
        for v in values { q.insert(v) }
        var prev = Int.min
        while let v = q.removeMin() {
            #expect(v >= prev)
            prev = v
        }
    }
}
