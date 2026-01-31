import Foundation
import Network

enum WHOISClient {
    // Common TLD -> WHOIS server mapping
    private static let whoisServers: [String: String] = [
        "com": "whois.verisign-grs.com",
        "net": "whois.verisign-grs.com",
        "org": "whois.pir.org",
        "info": "whois.afilias.net",
        "biz": "whois.biz",
        "us": "whois.nic.us",
        "co": "whois.nic.co",
        "io": "whois.nic.io",
        "me": "whois.nic.me",
        "tv": "whois.nic.tv",
        "cc": "whois.nic.cc",
        "mobi": "whois.dotmobiregistry.net",
        "name": "whois.nic.name",
        "pro": "whois.registrypro.pro",
        "tel": "whois.nic.tel",
        "asia": "whois.nic.asia",
        "cat": "whois.nic.cat",
        "jobs": "whois.nic.jobs",
        "travel": "whois.nic.travel",
        "coop": "whois.nic.coop",
        "museum": "whois.nic.museum",
        "aero": "whois.aero",
        "uk": "whois.nic.uk",
        "de": "whois.denic.de",
        "fr": "whois.nic.fr",
        "nl": "whois.sidn.nl",
        "au": "whois.auda.org.au",
        "ca": "whois.cira.ca",
        "eu": "whois.eu",
        "be": "whois.dns.be",
        "at": "whois.nic.at",
        "ch": "whois.nic.ch",
        "it": "whois.nic.it",
        "es": "whois.nic.es",
        "se": "whois.iis.se",
        "no": "whois.norid.no",
        "fi": "whois.fi",
        "dk": "whois.dk-hostmaster.dk",
        "pl": "whois.dns.pl",
        "cz": "whois.nic.cz",
        "ru": "whois.tcinet.ru",
        "jp": "whois.jprs.jp",
        "kr": "whois.kr",
        "cn": "whois.cnnic.cn",
        "br": "whois.registro.br",
        "mx": "whois.mx",
        "ar": "whois.nic.ar",
        "cl": "whois.nic.cl",
        "nz": "whois.srs.net.nz",
        "za": "whois.registry.net.za",
        "in": "whois.registry.in",
        "xyz": "whois.nic.xyz",
        "online": "whois.nic.online",
        "site": "whois.nic.site",
        "app": "whois.nic.google",
        "dev": "whois.nic.google",
    ]

    // Patterns indicating domain is not registered
    private static let notFoundPatterns = [
        "no match", "not found", "no entries", "no data found",
        "nothing found", "no information", "status: free",
        "status: available", "domain not found",
        "no match for", "this domain is not registered",
        "% no matching objects", "object does not exist",
    ]

    static func isAvailable(domain: String) async -> Bool {
        let tld = domain.split(separator: ".").last.map(String.init) ?? ""
        let server = whoisServers[tld] ?? "whois.iana.org"

        guard let response = await query(domain: domain, server: server) else {
            return false // Error = assume registered
        }

        let lower = response.lowercased()
        for pattern in notFoundPatterns {
            if lower.contains(pattern) { return true }
        }

        // If IANA, it might redirect to a specific server
        if server == "whois.iana.org" {
            for line in lower.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("refer:") {
                    let referServer = trimmed.dropFirst("refer:".count).trimmingCharacters(in: .whitespaces)
                    if !referServer.isEmpty {
                        if let resp2 = await query(domain: domain, server: referServer) {
                            let lower2 = resp2.lowercased()
                            for pattern in notFoundPatterns {
                                if lower2.contains(pattern) { return true }
                            }
                        }
                    }
                    break
                }
            }
        }

        return false
    }

    private static func query(domain: String, server: String) async -> String? {
        await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host(server)
            let port = NWEndpoint.Port(integerLiteral: 43)
            let connection = NWConnection(host: host, port: port, using: .tcp)

            let buffer = LockedBuffer()

            let queue = DispatchQueue(label: "whois.\(domain)")

            // Timeout
            queue.asyncAfter(deadline: .now() + 10) {
                connection.cancel()
                if buffer.tryResume() {
                    continuation.resume(returning: nil)
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let query = "\(domain)\r\n"
                    connection.send(content: query.data(using: .utf8), contentContext: .defaultMessage,
                                    isComplete: true, completion: .contentProcessed { _ in })

                    func readMore() {
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                            if let data { buffer.append(data) }
                            if isComplete || error != nil {
                                connection.cancel()
                                if buffer.tryResume() {
                                    let text = buffer.string
                                    continuation.resume(returning: text)
                                }
                            } else {
                                readMore()
                            }
                        }
                    }
                    readMore()

                case .failed, .cancelled:
                    if buffer.tryResume() {
                        continuation.resume(returning: nil)
                    }
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }
}

/// Thread-safe buffer for accumulating WHOIS response data with single-resume guarantee.
private final class LockedBuffer: @unchecked Sendable {
    private var data = Data()
    private var resumed = false
    private let lock = NSLock()

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    /// Returns true only on the first call (first caller wins).
    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return false }
        resumed = true
        return true
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii) ?? ""
    }
}
