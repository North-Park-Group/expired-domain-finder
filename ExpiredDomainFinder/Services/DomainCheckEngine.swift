import Foundation

/// DNS-first + WHOIS fallback domain availability checker.
actor DomainCheckEngine {
    private var tldSemaphores: [String: Int] = [:] // Track concurrent WHOIS per TLD
    private let maxPerTLD = 2

    func checkDomain(_ domain: String, retries: Int) async -> Bool {
        // DNS first - if resolves, domain is registered
        if await DNSResolver.resolves(domain: domain, timeout: 5) {
            return false // registered
        }

        // DNS failed - try WHOIS with per-TLD rate limiting
        let tld = domain.split(separator: ".").last.map(String.init) ?? ""

        // Simple per-TLD concurrency control
        while tldSemaphores[tld, default: 0] >= maxPerTLD {
            try? await Task.sleep(for: .milliseconds(200))
        }
        tldSemaphores[tld, default: 0] += 1
        defer { tldSemaphores[tld, default: 0] -= 1 }

        for attempt in 1...retries {
            let available = await WHOISClient.isAvailable(domain: domain)
            if available { return true }

            // If WHOIS returned false (registered or error), break unless it errored
            // We assume any response means we got an answer
            if attempt < retries {
                try? await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
            } else {
                break
            }
        }

        return false
    }
}
