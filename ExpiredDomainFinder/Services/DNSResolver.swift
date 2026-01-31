@preconcurrency import Dispatch
import Foundation

enum DNSResolver {
    /// Returns true if domain resolves via DNS (i.e., is registered/active).
    static func resolves(domain: String, timeout: TimeInterval = 5) async -> Bool {
        await withCheckedContinuation { continuation in
            let resumed = LockedBool()
            let workItem = DispatchWorkItem {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(domain, "80", &hints, &result)
                if let result { freeaddrinfo(result) }
                if resumed.setTrue() {
                    continuation.resume(returning: status == 0)
                }
            }
            DispatchQueue.global(qos: .utility).async(execute: workItem)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                workItem.cancel()
                if resumed.setTrue() {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

/// Thread-safe bool that returns true only on the first call to setTrue().
private final class LockedBool: @unchecked Sendable {
    private var value = false
    private let lock = NSLock()

    /// Sets to true and returns true only if it was previously false (first caller wins).
    func setTrue() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !value else { return false }
        value = true
        return true
    }
}
