import SwiftUI
import AppKit

struct ResultsTableView: View {
    let results: [DomainResult]
    let discoveredDomains: [String: Set<String>]
    let phase: ScanPhase
    let onExport: () -> Void

    @State private var selection: Set<DomainResult.ID> = []
    @State private var sortOrder = [KeyPathComparator(\DomainResult.linkCount, order: .reverse)]
    @State private var searchText = ""
    @State private var showDiscovered = false

    private var sortedResults: [DomainResult] {
        let filtered = searchText.isEmpty ? results : results.filter {
            $0.domain.localizedCaseInsensitiveContains(searchText)
        }
        return filtered.sorted(using: sortOrder)
    }

    private var discoveredCount: Int {
        discoveredDomains.count
    }

    var body: some View {
        VStack(spacing: 0) {
            if phase == .idle && results.isEmpty {
                emptyState
            } else if phase == .crawling || phase == .seeding {
                crawlingLiveView
            } else {
                resultsTable
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "globe.desk")
                .font(.system(size: 44))
                .foregroundStyle(Color.npAccent.opacity(0.25))
            VStack(spacing: 8) {
                Text("Enter a URL to find expired domains")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Text("The scanner will crawl the site, extract external links, and check which domains are available for registration.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var crawlingLiveView: some View {
        VStack(spacing: 0) {
            // Header — always visible
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDiscovered.toggle()
                }
            } label: {
                HStack {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.npAccent)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .fill(Color.npAccent.opacity(0.3))
                                    .frame(width: 14, height: 14)
                            )
                        Text("Discovered External Domains")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text("\(discoveredCount)")
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.npAccent)
                            .contentTransition(.numericText())
                            .animation(.default, value: discoveredCount)
                    }
                    Spacer()
                    if !discoveredDomains.isEmpty {
                        Image(systemName: showDiscovered ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if discoveredDomains.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.npAccent)
                    Text("Scanning for external domains...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if showDiscovered {
                List {
                    ForEach(discoveredDomains.sorted(by: { $0.value.count > $1.value.count }), id: \.key) { domain, sources in
                        HStack {
                            Text(domain)
                                .font(.body)
                            Spacer()
                            Text("\(sources.count)")
                                .foregroundStyle(.white)
                                .monospacedDigit()
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.npAccent.opacity(0.75)))
                        }
                        .contextMenu {
                            domainContextMenu(domain: domain)
                        }
                    }
                }
            } else {
                // Collapsed — just show a subtle hint
                HStack {
                    Text("Availability will be checked after crawl completes")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                Spacer()
            }
        }
    }

    private var resultsTable: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.npGreen)
                    Text("Available Domains")
                        .font(.title3)
                        .fontWeight(.medium)
                    Text("\(results.count)")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.npGreen)
                        .contentTransition(.numericText())
                        .animation(.default, value: results.count)
                }
                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 12))
                    TextField("Filter domains...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 140)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.npSurfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.npBorder, lineWidth: 1)
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if results.isEmpty && (phase == .checking || phase == .done || phase == .cancelled) {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: phase == .checking ? "magnifyingglass" : "xmark.circle")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                    Text(phase == .checking ? "Checking domains..." : "No available domains found")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(sortedResults, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Domain", value: \.domain) { result in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.npGreen)
                                .frame(width: 6, height: 6)
                            Text(result.domain)
                                .font(.body)
                        }
                        .contextMenu {
                            domainContextMenu(domain: result.domain)
                        }
                    }
                    .width(min: 150, ideal: 200)

                    TableColumn("Links", value: \.linkCount) { result in
                        Text("\(result.linkCount)")
                            .font(.body)
                            .monospacedDigit()
                            .foregroundStyle(Color.npAccent)
                            .fontWeight(.medium)
                    }
                    .width(50)

                    TableColumn("History") { result in
                        Button {
                            if let url = URL(string: "https://web.archive.org/web/*/\(result.domain)") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 11))
                                Text("Wayback")
                                    .font(.caption)
                            }
                            .foregroundStyle(Color.npAccent)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                    .width(80)

                    TableColumn("Found On") { result in
                        Text(result.foundOnDisplay)
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 200, ideal: 400)
                }
            }
        }
    }

    @ViewBuilder
    private func domainContextMenu(domain: String) -> some View {
        Button("Copy Domain") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(domain, forType: .string)
        }
        Button("Open in Browser") {
            if let url = URL(string: "https://\(domain)") {
                NSWorkspace.shared.open(url)
            }
        }
        Button("WHOIS Lookup") {
            if let url = URL(string: "https://who.is/whois/\(domain)") {
                NSWorkspace.shared.open(url)
            }
        }
        Button("View on Wayback Machine") {
            if let url = URL(string: "https://web.archive.org/web/*/\(domain)") {
                NSWorkspace.shared.open(url)
            }
        }
        Divider()
        Button("Copy All Selected Domains") {
            let domains = results.filter { selection.contains($0.id) }.map(\.domain).joined(separator: "\n")
            if !domains.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(domains, forType: .string)
            }
        }
        .disabled(selection.isEmpty)
    }
}
