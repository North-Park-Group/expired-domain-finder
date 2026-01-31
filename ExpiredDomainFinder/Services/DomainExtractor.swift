import Foundation

/// Public Suffix List trie-based domain extractor (replaces tldextract).
actor DomainExtractor {
    static let shared = DomainExtractor()

    private final class TrieNode {
        var children: [String: TrieNode] = [:]
        var isEnd = false
        var isException = false // '!' rules
        var isWildcard = false  // '*' rules
    }

    private let root = TrieNode()
    private var loaded = false

    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let url = Bundle.main.url(forResource: "public_suffix_list", withExtension: "dat"),
              let data = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in data.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") { continue }
            insertRule(String(trimmed))
        }
    }

    private func insertRule(_ rule: String) {
        var r = rule
        let isException = r.hasPrefix("!")
        if isException { r = String(r.dropFirst()) }

        let labels = r.lowercased().split(separator: ".").reversed().map(String.init)
        var node = root
        for label in labels {
            if node.children[label] == nil {
                node.children[label] = TrieNode()
            }
            node = node.children[label]!
        }
        node.isEnd = true
        if isException { node.isException = true }
        if labels.last == "*" { node.children["*"]?.isWildcard = true }
    }

    /// Extract registrable domain from a hostname.
    /// e.g. "blog.example.co.uk" → "example.co.uk"
    func registrableDomain(from hostname: String) -> String? {
        loadIfNeeded()
        let labels = hostname.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .split(separator: ".")
            .map(String.init)

        guard labels.count >= 2 else { return nil }

        // Find suffix length by walking trie
        let reversed = Array(labels.reversed())
        var node = root
        var suffixLen = 0

        for (i, label) in reversed.enumerated() {
            if let child = node.children[label] {
                suffixLen = i + 1
                if child.isException {
                    // Exception rule: the suffix is one less
                    suffixLen = i
                    break
                }
                node = child
            } else if let wild = node.children["*"] {
                suffixLen = i + 1
                if wild.isException {
                    suffixLen = i
                    break
                }
                node = wild
            } else {
                break
            }
        }

        // Default: if nothing matched, assume single-label TLD
        if suffixLen == 0 { suffixLen = 1 }

        // registrable = suffix + 1 label
        let regLen = suffixLen + 1
        guard labels.count >= regLen else { return nil }

        let domainLabels = labels.suffix(regLen)
        let domain = domainLabels.joined(separator: ".")
        let domainLabel = String(domainLabels.first!)

        // Filter short / suspect domain labels
        if domainLabel.count <= 2 { return nil }
        if ExcludedDomains.suspectDomainLabels.contains(domainLabel) { return nil }

        return domain
    }
}
