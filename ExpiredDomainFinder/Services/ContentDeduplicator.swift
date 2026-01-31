import CryptoKit
import Foundation

actor ContentDeduplicator {
    private var hashes: [String] = []
    private var hashSet: Set<String> = []
    private let maxEntries: Int

    init(maxEntries: Int = 10_000) {
        self.maxEntries = maxEntries
    }

    /// Returns true if this content is a duplicate (already seen).
    func isDuplicate(html: String) -> Bool {
        // Hash characters 2048-6144 to skip shared header/nav
        let start = html.index(html.startIndex, offsetBy: min(2048, html.count))
        let end = html.index(html.startIndex, offsetBy: min(6144, html.count))
        let slice = html[start..<end]
        let data = Data(slice.utf8)
        let digest = Insecure.MD5.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        if hashSet.contains(hex) { return true }

        // Evict oldest entry if at capacity
        if hashes.count >= maxEntries {
            let evicted = hashes.removeFirst()
            hashSet.remove(evicted)
        }

        hashes.append(hex)
        hashSet.insert(hex)
        return false
    }

    func reset() {
        hashes.removeAll()
        hashSet.removeAll()
    }
}
