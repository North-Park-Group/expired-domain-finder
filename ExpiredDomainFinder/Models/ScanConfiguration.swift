import Foundation

enum ScanPreset: String, CaseIterable, Identifiable {
    case quick, standard, deep, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quick: "Quick"
        case .standard: "Standard"
        case .deep: "Deep"
        case .custom: "Custom"
        }
    }

    var icon: String {
        switch self {
        case .quick: "hare"
        case .standard: "scope"
        case .deep: "tortoise"
        case .custom: "gearshape"
        }
    }
}

enum JSRenderMode: String, CaseIterable, Identifiable {
    case allPages, fallback, sample

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allPages: "All Pages"
        case .fallback: "Fallback"
        case .sample: "Sample"
        }
    }

    var description: String {
        switch self {
        case .allPages: "Render every page with JavaScript. Thorough but slower."
        case .fallback: "Try HTML first, re-render with JS if few links found."
        case .sample: "Render a sample of pages to discover JS-only link patterns."
        }
    }

    var icon: String {
        switch self {
        case .allPages: "globe"
        case .fallback: "arrow.triangle.branch"
        case .sample: "sparkle.magnifyingglass"
        }
    }
}

@Observable
final class ScanConfiguration {
    var url: String = UserDefaults.standard.string(forKey: "lastURL") ?? ""
    var bulkInput: String = ""
    var isBulkMode: Bool = false
    var maxPages: Int = 500
    var maxDepth: Int = 10
    var crawlWorkers: Int = 10
    var checkWorkers: Int = 20
    var delay: Double = 0.1
    var retries: Int = 3
    var useSitemaps: Bool = true
    var useWayback: Bool = false
    var excludedDomains: String = ""
    var preset: ScanPreset = .standard
    var jsRenderingEnabled: Bool = false
    var jsRenderMode: JSRenderMode = .fallback
    /// Number of pages to sample when using .sample mode
    var jsSampleSize: Int = 20
    /// Minimum link threshold for fallback mode — re-render if HTML yields fewer links than this
    var jsFallbackThreshold: Int = 3

    var parsedExcludedDomains: Set<String> {
        Set(excludedDomains.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
    }

    /// Returns the list of URLs to scan based on mode
    var urls: [String] {
        if isBulkMode {
            return bulkInput
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } else {
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }
    }

    func applyPreset(_ preset: ScanPreset) {
        self.preset = preset
        switch preset {
        case .quick:
            maxPages = 100; maxDepth = 3; crawlWorkers = 5
            jsRenderingEnabled = false
        case .standard:
            maxPages = 500; maxDepth = 10; crawlWorkers = 10
            jsRenderingEnabled = false
        case .deep:
            maxPages = 2000; maxDepth = 20; crawlWorkers = 15
            jsRenderingEnabled = true; jsRenderMode = .fallback
        case .custom:
            break
        }
    }

    func saveLastURL() {
        UserDefaults.standard.set(url, forKey: "lastURL")
    }
}
