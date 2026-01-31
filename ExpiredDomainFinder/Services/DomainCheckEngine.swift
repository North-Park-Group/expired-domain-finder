import Foundation

/// DNS-first + WHOIS fallback domain availability checker.
actor DomainCheckEngine {
    private var tldSemaphores: [String: AsyncSemaphore] = [:]
    private let maxPerTLD = 2

    private func semaphore(for tld: String) -> AsyncSemaphore {
        if let existing = tldSemaphores[tld] { return existing }
        let sem = AsyncSemaphore(limit: maxPerTLD)
        tldSemaphores[tld] = sem
        return sem
    }

    func checkDomain(_ domain: String, retries: Int) async -> Bool {
        // DNS first - if resolves, domain is registered
        if await DNSResolver.resolves(domain: domain, timeout: 5) {
            return false // registered
        }

        // DNS failed - try WHOIS with per-TLD rate limiting
        let tld = domain.split(separator: ".").last.map(String.init) ?? ""
        let sem = semaphore(for: tld)

        await sem.wait()
        let result = await whoisCheck(domain: domain, retries: retries)
        await sem.signal()

        return result
    }

    private nonisolated func whoisCheck(domain: String, retries: Int) async -> Bool {
        for attempt in 1...retries {
            let available = await WHOISClient.isAvailable(domain: domain)
            if available { return true }

            if attempt < retries {
                try? await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
            } else {
                break
            }
        }
        return false
    }
}

/// Async semaphore that suspends waiters instead of busy-looping.
actor AsyncSemaphore {
    private let limit: Int
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
        self.count = limit
    }

    func wait() async {
        if count > 0 {
            count -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            count += 1
        }
    }
}
