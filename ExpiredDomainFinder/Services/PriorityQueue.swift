import Foundation

/// Generic min-heap priority queue.
struct PriorityQueue<Element: Comparable> {
    private var heap: [Element] = []

    var isEmpty: Bool { heap.isEmpty }
    var count: Int { heap.count }

    mutating func insert(_ element: Element) {
        heap.append(element)
        siftUp(from: heap.count - 1)
    }

    mutating func removeMin() -> Element? {
        guard !heap.isEmpty else { return nil }
        if heap.count == 1 { return heap.removeLast() }
        let top = heap[0]
        heap[0] = heap.removeLast()
        siftDown(from: 0)
        return top
    }

    var min: Element? { heap.first }

    private mutating func siftUp(from index: Int) {
        var i = index
        while i > 0 {
            let parent = (i - 1) / 2
            if heap[i] < heap[parent] {
                heap.swapAt(i, parent)
                i = parent
            } else { break }
        }
    }

    private mutating func siftDown(from index: Int) {
        var i = index
        while true {
            let left = 2 * i + 1, right = 2 * i + 2
            var smallest = i
            if left < heap.count && heap[left] < heap[smallest] { smallest = left }
            if right < heap.count && heap[right] < heap[smallest] { smallest = right }
            if smallest == i { break }
            heap.swapAt(i, smallest)
            i = smallest
        }
    }
}
