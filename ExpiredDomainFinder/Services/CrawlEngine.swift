import Foundation

/// Async crawl orchestrator with priority queue and TaskGroup.
actor CrawlEngine {
    struct CrawlResult {
        let visited: Set<String>
        let domainSources: [String: Set<String>]
    }

    private let client = NetworkClient.shared
    private let dedup = ContentDeduplicator()
    private let domainExtractor = DomainExtractor.shared

    // Priority queue item
    private struct QueueItem: Comparable {
        let priority: Int
        let counter: Int
        let url: String
        let depth: Int

        static func < (lhs: QueueItem, rhs: QueueItem) -> Bool {
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.counter < rhs.counter
        }
    }

    func crawl(
        startURL: String,
        config: ScanConfiguration,
        onProgress: @Sendable @escaping (Int, Int, Int, Int) -> Void, // visited, maxPages, domainCount, depth
        onStatus: @Sendable @escaping (String) -> Void,
        onDomainDiscovered: @Sendable @escaping (String, String) -> Void, // domain, sourceURL
        onPageCrawled: @Sendable @escaping (String, Int) -> Void, // pageURL, linkCount
        isCancelled: @Sendable @escaping () -> Bool
    ) async -> CrawlResult {
        await domainExtractor.loadIfNeeded()

        guard let startParsed = URLComponents(string: startURL) else {
            return CrawlResult(visited: [], domainSources: [:])
        }

        var baseDomain = (startParsed.host ?? "").lowercased()
        let regDomain = await domainExtractor.registrableDomain(from: baseDomain) ?? baseDomain

        var visited: Set<String> = []
        var enqueued: Set<String> = []
        var domainSources: [String: Set<String>] = [:]
        var counter = 0

        // JS rendering state
        let jsEnabled = config.jsRenderingEnabled
        let jsMode = config.jsRenderMode
        let jsSampleSize = config.jsSampleSize
        let jsFallbackThreshold = config.jsFallbackThreshold
        var jsSampledCount = 0

        // Warm up JS renderer if needed
        if jsEnabled {
            await JSRendererPool.shared.warmUp()
            onStatus("JavaScript rendering enabled (\(jsMode.label) mode)")
        }

            var queue = PriorityQueue<QueueItem>()

        func enqueue(_ url: String, depth: Int) {
            guard !visited.contains(url), !enqueued.contains(url),
                  enqueued.count < config.maxPages * 5 else { return }
            let prio = URLPriority.priority(for: url, depth: depth)
            counter += 1
            queue.insert(QueueItem(priority: prio, counter: counter, url: url, depth: depth))
            enqueued.insert(url)
        }

        func isSameSite(_ domain: String) -> Bool {
            domain == regDomain || domain.hasSuffix("." + regDomain)
        }

        // Seed start URL
        if let norm = URLNormalizer.normalize(startURL) {
            enqueue(norm, depth: 0)
        }

        // Follow redirects on start URL
        if let startURLObj = URL(string: startURL) {
            if let (_, response) = try? await client.fetch(url: startURLObj) {
                if let effectiveURL = response.url,
                   let effectiveDomain = effectiveURL.host?.lowercased(),
                   effectiveDomain != baseDomain {
                    baseDomain = effectiveDomain
                    if let norm = URLNormalizer.normalize(effectiveURL.absoluteString) {
                        enqueue(norm, depth: 0)
                    }
                }
            }
        }

        let effectiveBase = "\(startParsed.scheme ?? "https")://\(baseDomain)"

        // Seeding
        if config.useSitemaps && !isCancelled() {
            onStatus("Fetching sitemaps...")
            let robotsSitemaps = await RobotsTxtSeeder.fetchSitemapURLs(baseURL: effectiveBase, client: client)
            let sitemapURLs = await SitemapSeeder.fetchURLs(baseURL: effectiveBase, extraSitemapURLs: robotsSitemaps, client: client)
            for u in sitemapURLs { enqueue(u, depth: 1) }
            onStatus("Seeded \(sitemapURLs.count) sitemap URLs")

            if !isCancelled() {
                onStatus("Fetching RSS feeds...")
                let rssURLs = await RSSSeeder.fetchURLs(baseURL: effectiveBase, client: client)
                for u in rssURLs { enqueue(u, depth: 1) }
            }

            if !isCancelled() {
                onStatus("Detecting WordPress...")
                let wpURLs = await WordPressSeeder.fetchURLs(baseURL: effectiveBase, client: client)
                if !wpURLs.isEmpty {
                    for u in wpURLs { enqueue(u, depth: 1) }
                    onStatus("WordPress detected — seeded \(wpURLs.count) URLs from WP API")
                }
            }
        }

        if config.useWayback && !isCancelled() {
            onStatus("Fetching Wayback Machine URLs...")
            let waybackURLs = await WaybackSeeder.fetchURLs(baseDomain: regDomain, client: client)
            for u in waybackURLs {
                if let comp = URLComponents(string: u), let h = comp.host?.lowercased(), isSameSite(h) {
                    enqueue(u, depth: 2)
                }
            }
            onStatus("Seeded \(waybackURLs.count) Wayback URLs")

            if !isCancelled() {
                onStatus("Fetching Common Crawl URLs...")
                let ccURLs = await CommonCrawlSeeder.fetchURLs(baseDomain: regDomain, client: client)
                for u in ccURLs {
                    if let comp = URLComponents(string: u), let h = comp.host?.lowercased(), isSameSite(h) {
                        enqueue(u, depth: 2)
                    }
                }
                onStatus("Seeded \(ccURLs.count) Common Crawl URLs")
            }
        }

        guard !isCancelled() else {
            return CrawlResult(visited: [], domainSources: [:])
        }

        onStatus("Crawling \(queue.count) queued URLs...")

        // Crawl loop with concurrency
        let maxConcurrency = config.crawlWorkers
        let delay = config.delay

        // Streaming crawl loop — process results as they arrive for smooth UI
        var active = 0
        await withTaskGroup(of: PageResult.self) { group in
            // Fill initial worker slots
            func fillWorkers() {
                while active < maxConcurrency && !queue.isEmpty && visited.count + active < config.maxPages && !isCancelled() {
                    guard let item = queue.removeMin() else { break }
                    if visited.contains(item.url) { continue }

                    var useJS = false
                    if jsEnabled {
                        switch jsMode {
                        case .allPages: useJS = true
                        case .sample:
                            if jsSampledCount < jsSampleSize {
                                useJS = true
                                jsSampledCount += 1
                            }
                        case .fallback: break
                        }
                    }

                    active += 1
                    group.addTask {
                        await self.processPage(item: item, baseDomain: baseDomain,
                                               regDomain: regDomain, isSameSite: isSameSite,
                                               delay: delay, useJS: useJS)
                    }
                }
            }

            fillWorkers()

            for await result in group {
                active -= 1
                guard !isCancelled() else { break }
                guard visited.count < config.maxPages else { break }

                // JS fallback: re-render if too few links
                var finalResult = result
                if jsEnabled && jsMode == .fallback && result.externalDomains != nil {
                    let totalLinks = result.internalLinks.count + (result.externalDomains?.count ?? 0)
                    if totalLinks < jsFallbackThreshold {
                        let reRendered = await self.processPage(
                            item: result.item, baseDomain: baseDomain,
                            regDomain: regDomain, isSameSite: isSameSite,
                            delay: 0, useJS: true)
                        let newCount = reRendered.internalLinks.count + (reRendered.externalDomains?.count ?? 0)
                        if newCount > totalLinks { finalResult = reRendered }
                    }
                }

                visited.insert(finalResult.item.url)

                let totalLinks = (finalResult.externalDomains?.count ?? 0) + finalResult.internalLinks.count
                onPageCrawled(finalResult.item.url, totalLinks)

                if let externals = finalResult.externalDomains {
                    for (link, newDepth) in finalResult.internalLinks {
                        if newDepth <= config.maxDepth {
                            enqueue(link, depth: newDepth)
                        }
                    }
                    for (link, depth) in finalResult.paginationLinks {
                        if depth <= config.maxDepth {
                            enqueue(link, depth: depth)
                        }
                    }
                    for (domain, sourceURL) in externals {
                        let isNew = domainSources[domain] == nil
                        domainSources[domain, default: []].insert(sourceURL)
                        if isNew {
                            onDomainDiscovered(domain, sourceURL)
                        }
                    }
                }

                onProgress(visited.count, config.maxPages, domainSources.count, finalResult.item.depth)

                // Refill workers immediately
                fillWorkers()
            }
        }

        // Shut down JS renderer if we used it
        if jsEnabled {
            await JSRendererPool.shared.shutdown()
        }

        return CrawlResult(visited: visited, domainSources: domainSources)
    }

    private struct PageResult {
        let item: QueueItem
        let internalLinks: [(String, Int)]
        let externalDomains: [(String, String)]?
        let paginationLinks: [(String, Int)]
        var error: CrawlError? = nil

        /// Convenience for error/skip results with no links.
        static func empty(_ item: QueueItem, error: CrawlError? = nil) -> PageResult {
            PageResult(item: item, internalLinks: [], externalDomains: nil, paginationLinks: [], error: error)
        }
    }

    private func processPage(
        item: QueueItem,
        baseDomain: String,
        regDomain: String,
        isSameSite: (String) -> Bool,
        delay: Double,
        useJS: Bool = false
    ) async -> PageResult {
        if delay > 0 {
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
        }

        guard let url = URL(string: item.url) else {
            return .empty(item, error: .invalidURL(item.url))
        }

        let text: String

        if useJS {
            guard let html = await JSRendererPool.shared.renderHTML(url: url) else {
                return .empty(item, error: .timeout(url: item.url))
            }
            text = html
        } else {
            let fetchedText: String
            do {
                let (t, response) = try await client.fetchString(url: url, timeout: 15)
                guard (200..<300).contains(response.statusCode) else {
                    return .empty(item, error: .httpError(url: item.url, statusCode: response.statusCode))
                }
                let ct = response.value(forHTTPHeaderField: "Content-Type") ?? ""
                guard ct.contains("text/html") else {
                    return .empty(item, error: .nonHTMLContent(url: item.url, contentType: ct))
                }
                fetchedText = t
            } catch {
                return .empty(item, error: .networkFailure(url: item.url, underlying: error))
            }
            text = fetchedText
        }

        // Content dedup
        if await dedup.isDuplicate(html: text) {
            return .empty(item)
        }

        let extracted = HTMLParser.extractURLs(html: text, baseURL: item.url)
        var internalLinks: [(String, Int)] = []
        var externalDomains: [(String, String)] = []
        var paginationLinks: [(String, Int)] = []

        for foundURL in extracted.crawlURLs {
            guard let comp = URLComponents(string: foundURL),
                  let scheme = comp.scheme, ["http", "https"].contains(scheme),
                  let host = comp.host?.lowercased() else { continue }
            if isSameSite(host) {
                if let norm = URLNormalizer.normalize(foundURL) {
                    internalLinks.append((norm, item.depth + 1))
                }
            }
        }

        // Pagination links get special handling — same depth, high priority
        for foundURL in extracted.paginationURLs {
            guard let comp = URLComponents(string: foundURL),
                  let scheme = comp.scheme, ["http", "https"].contains(scheme),
                  let host = comp.host?.lowercased() else { continue }
            if isSameSite(host) {
                if let norm = URLNormalizer.normalize(foundURL) {
                    paginationLinks.append((norm, item.depth))
                }
            }
        }

        for foundURL in extracted.anchorURLs {
            guard let comp = URLComponents(string: foundURL),
                  let scheme = comp.scheme, ["http", "https"].contains(scheme),
                  let host = comp.host?.lowercased() else { continue }
            if !isSameSite(host) {
                if let extDomain = await domainExtractor.registrableDomain(from: host) {
                    externalDomains.append((extDomain, item.url))
                }
            }
        }

        return PageResult(item: item, internalLinks: internalLinks, externalDomains: externalDomains, paginationLinks: paginationLinks)
    }
}

// MARK: - Global JS Renderer Pool (main-actor bound)

@MainActor
final class JSRendererPool {
    static let shared = JSRendererPool()
    private var renderer: JSRenderer?

    func warmUp() {
        if renderer == nil {
            renderer = JSRenderer(poolSize: 3)
        }
        renderer?.warmUp()
    }

    func renderHTML(url: URL, timeout: TimeInterval = 10) async -> String? {
        await renderer?.renderHTML(url: url, timeout: timeout)
    }

    func shutdown() {
        renderer?.shutdown()
        renderer = nil
    }
}
