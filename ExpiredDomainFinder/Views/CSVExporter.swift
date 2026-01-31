import AppKit
import Foundation
import UniformTypeIdentifiers

enum CSVExporter {
    static func export(results: [DomainResult]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "csv") ?? .commaSeparatedText]
        panel.nameFieldStringValue = "expired_domains_report.csv"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var csv = "domain,link_count,found_on\n"
        let sorted = results.sorted {
            $0.linkCount > $1.linkCount || ($0.linkCount == $1.linkCount && $0.domain < $1.domain)
        }
        for r in sorted {
            let foundOn = r.foundOn.joined(separator: " | ")
            let escaped = foundOn.contains(",") || foundOn.contains("\"")
                ? "\"\(foundOn.replacingOccurrences(of: "\"", with: "\"\""))\"" : foundOn
            csv += "\(r.domain),\(r.linkCount),\(escaped)\n"
        }

        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
