import Foundation
import SwiftUI

@Observable
final class AppState {
    var phase: ScanPhase = .idle
    var config = ScanConfiguration()
    var results: [DomainResult] = []
    var discoveredDomains: [String: Set<String>] = [:]
    var pagesVisited = 0
    var maxPages = 500
    var domainCount = 0
    var currentDepth = 0
    var domainsChecked = 0
    var domainsToCheck = 0
    var statusMessage = ""
    var crawlStartTime: Date?
    var totalPagesAtEnd = 0

    // Multi-domain tracking
    var currentScanIndex = 0
    var totalScans = 0
    var currentScanURL = ""

    // Activity log
    var activityLog: [ActivityEntry] = []

    private var scanTask: Task<Void, Never>?
    private let crawlEngine = CrawlEngine()
    private let checkEngine = DomainCheckEngine()

    var isRunning: Bool {
        phase != .idle && phase != .done && phase != .cancelled
    }

    var progress: Double {
        switch phase {
        case .crawling:
            guard maxPages > 0 else { return 0 }
            return Double(pagesVisited) / Double(maxPages)
        case .checking:
            guard domainsToCheck > 0 else { return 0 }
            return Double(domainsChecked) / Double(domainsToCheck)
        default:
            return 0
        }
    }

    var pagesPerSecond: Double {
        guard let start = crawlStartTime, pagesVisited > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return 0 }
        return Double(pagesVisited) / elapsed
    }

    @MainActor
    func addActivity(_ message: String, type: ActivityType) {
        let entry = ActivityEntry(date: Date(), message: message, type: type)
        activityLog.append(entry)
        if activityLog.count > 200 {
            activityLog.removeFirst(activityLog.count - 200)
        }
    }

    func startScan() {
        guard !isRunning else { return }

        let rawURLs = config.urls
        guard !rawURLs.isEmpty else {
            statusMessage = "Enter at least one URL"
            return
        }

        let urls = rawURLs.map { u -> String in
            var u = u
            if !u.contains("://") { u = "https://" + u }
            return u
        }.filter { URL(string: $0) != nil }

        guard !urls.isEmpty else {
            statusMessage = "No valid URLs found"
            return
        }

        config.saveLastURL()

        results = []
        discoveredDomains = [:]
        activityLog = []
        pagesVisited = 0
        maxPages = config.maxPages
        domainCount = 0
        currentDepth = 0
        domainsChecked = 0
        domainsToCheck = 0
        totalPagesAtEnd = 0
        statusMessage = ""
        crawlStartTime = nil
        currentScanIndex = 0
        totalScans = urls.count
        currentScanURL = ""
        phase = .seeding

        let configSnapshot = config
        let extraExcludes = config.parsedExcludedDomains

        scanTask = Task { [weak self] in
            guard let self else { return }

            // Stream for pipelining: crawl feeds domains, checker consumes them
            let (domainStream, domainContinuation) = AsyncStream<(String, Set<String>)>.makeStream()

            // Track all domain sources for result building
            var allDomainSources: [String: Set<String>] = [:]
            var allVisitedCount = 0

            // Background checker task — runs concurrently with crawling
            let checkerTask = Task { [weak self] in
                guard let self else { return }
                let concurrency = configSnapshot.checkWorkers
                let retries = configSnapshot.retries

                await withTaskGroup(of: (String, Set<String>, Bool).self) { group in
                    var active = 0

                    for await (domain, sources) in domainStream {
                        if Task.isCancelled { break }

                        // Drain completed checks to stay under concurrency limit
                        while active >= concurrency {
                            if let (d, srcs, available) = await group.next() {
                                active -= 1
                                await self.handleCheckResult(domain: d, available: available, sources: srcs)
                            }
                        }

                        if Task.isCancelled { break }

                        let d = domain
                        let srcs = sources
                        group.addTask {
                            let available = await self.checkEngine.checkDomain(d, retries: retries)
                            return (d, srcs, available)
                        }
                        active += 1
                    }

                    // Drain remaining checks
                    for await (d, srcs, available) in group {
                        await self.handleCheckResult(domain: d, available: available, sources: srcs)
                    }
                }
            }

            // Phase 1: Crawl — discovered domains are streamed to checker
            for (index, url) in urls.enumerated() {
                guard !Task.isCancelled else { break }

                await MainActor.run {
                    self.currentScanIndex = index + 1
                    self.currentScanURL = url
                    self.pagesVisited = 0
                    self.domainCount = 0
                    self.currentDepth = 0
                    self.crawlStartTime = nil
                    self.phase = .seeding
                    self.statusMessage = "Seeding URLs..."
                    self.addActivity("Starting scan \(index + 1) of \(urls.count): \(url)", type: .info)
                }

                let crawlResult = await crawlEngine.crawl(
                    startURL: url,
                    config: configSnapshot,
                    onProgress: { visited, max, domains, depth in
                        Task { @MainActor in
                            self.pagesVisited = visited
                            self.maxPages = max
                            self.domainCount = domains
                            self.currentDepth = depth
                            if self.phase == .seeding {
                                self.phase = .crawling
                                self.crawlStartTime = Date()
                                self.statusMessage = ""
                            }
                        }
                    },
                    onStatus: { message in
                        Task { @MainActor in
                            self.statusMessage = message
                            self.addActivity(message, type: .seeding)
                        }
                    },
                    onDomainDiscovered: { domain, sourceURL in
                        Task { @MainActor in
                            self.discoveredDomains[domain, default: []].insert(sourceURL)
                            self.addActivity("Found: \(domain)", type: .domain)
                        }
                    },
                    onPageCrawled: { pageURL, linkCount in
                        Task { @MainActor in
                            self.addActivity("Crawled: \(pageURL) (\(linkCount) links)", type: .crawl)
                        }
                    },
                    isCancelled: { Task.isCancelled }
                )

                guard !Task.isCancelled else { break }

                // Accumulate and feed new domains to checker
                for (domain, sources) in crawlResult.domainSources {
                    allDomainSources[domain, default: []].formUnion(sources)
                }
                allVisitedCount += crawlResult.visited.count

                // Filter and send newly discovered domains to the checker stream
                for (domain, sources) in crawlResult.domainSources {
                    if !ExcludedDomains.shouldExclude(domain: domain, extra: extraExcludes) {
                        domainContinuation.yield((domain, sources))
                    }
                }
            }

            // Signal no more domains coming
            domainContinuation.finish()

            let totalFiltered = allDomainSources.keys.filter {
                !ExcludedDomains.shouldExclude(domain: $0, extra: extraExcludes)
            }.count
            let visitedSnapshot = allVisitedCount

            await MainActor.run {
                self.domainsToCheck = totalFiltered
                self.totalPagesAtEnd = visitedSnapshot
                self.phase = .checking
                self.statusMessage = "Crawling complete — finishing domain checks..."
                self.addActivity("Crawling complete. Waiting for \(totalFiltered - self.domainsChecked) remaining checks...", type: .info)
            }

            // Wait for checker to finish
            await checkerTask.value

            guard !Task.isCancelled else {
                await MainActor.run { self.phase = .cancelled }
                return
            }

            await MainActor.run {
                self.statusMessage = "Scan complete: \(self.results.count) available domains found from \(self.totalPagesAtEnd) pages"
                self.phase = .done
                self.addActivity("Done! \(self.results.count) available domains found.", type: .info)
            }
        }
    }

    private func handleCheckResult(domain: String, available: Bool, sources: Set<String>) async {
        await MainActor.run {
            self.domainsChecked += 1
            if available {
                let srcs = Array(sources).sorted()
                let result = DomainResult(domain: domain, linkCount: srcs.count, foundOn: srcs)
                self.results.append(result)
                self.results.sort { $0.linkCount > $1.linkCount || ($0.linkCount == $1.linkCount && $0.domain < $1.domain) }
                self.addActivity("Available: \(domain)", type: .check)
            }
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        phase = .cancelled
    }
}
