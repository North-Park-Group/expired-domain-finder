import SwiftUI

struct ScanProgressView: View {
    let phase: ScanPhase
    let pagesVisited: Int
    let maxPages: Int
    let domainCount: Int
    let currentDepth: Int
    let domainsChecked: Int
    let domainsToCheck: Int
    let progress: Double
    let statusMessage: String
    let pagesPerSecond: Double
    let activityLog: [ActivityEntry]
    let currentScanIndex: Int
    let totalScans: Int
    let currentScanURL: String

    @State private var showActivity = true

    var body: some View {
        if phase != .idle {
            VStack(spacing: 12) {
                // Multi-domain header
                if totalScans > 1 {
                    HStack(spacing: 6) {
                        Text("Scan \(currentScanIndex)/\(totalScans)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.npAccent))
                        Text(currentScanURL)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                }

                // Phase + stats
                HStack {
                    Label(phaseLabel, systemImage: phaseIcon)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(phaseColor)
                    Spacer()
                    Text(statsLabel)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.default, value: pagesVisited)
                        .animation(.default, value: domainsChecked)
                        .animation(.default, value: domainCount)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.npBorder)
                        if phase == .seeding {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.npAccent.opacity(0.6), Color.npAccent, Color.npAccent.opacity(0.6)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * 0.3)
                                .offset(x: geo.size.width * 0.35)
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: progressGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, geo.size.width * progress))
                                .animation(.easeInOut(duration: 0.3), value: progress)
                        }
                    }
                }
                .frame(height: 6)

                // Status message (non-done)
                if !statusMessage.isEmpty && phase != .done {
                    HStack {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                }

                // Done banner
                if phase == .done {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.npGreen)
                        Text(statusMessage)
                            .font(.body)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.npGreenSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Activity log
                if !activityLog.isEmpty {
                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showActivity.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showActivity ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("Activity")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(activityLog.count)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 4)

                        if showActivity {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 2) {
                                        ForEach(activityLog) { entry in
                                            ActivityRow(entry: entry)
                                                .id(entry.id)
                                        }
                                    }
                                    .padding(8)
                                }
                                .frame(maxHeight: 120)
                                .background(Color.npSurfaceRaised)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.npBorder, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onChange(of: activityLog.count) {
                                    if let last = activityLog.last {
                                        withAnimation {
                                            proxy.scrollTo(last.id, anchor: .bottom)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.npSurfaceRaised)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.npBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .idle: .secondary
        case .seeding, .crawling, .checking: Color.npAccent
        case .done: Color.npGreen
        case .cancelled: .secondary
        }
    }

    private var progressGradient: [Color] {
        switch phase {
        case .done: [Color.npGreen, Color.npGreen.opacity(0.85)]
        default: [Color.npAccent, Color.npAccentLight]
        }
    }

    private var phaseLabel: String {
        switch phase {
        case .idle: ""
        case .seeding: "Seeding"
        case .crawling: "Crawling"
        case .checking: "Checking Domains"
        case .done: "Complete"
        case .cancelled: "Cancelled"
        }
    }

    private var phaseIcon: String {
        switch phase {
        case .idle: "circle"
        case .seeding: "arrow.down.circle"
        case .crawling: "globe"
        case .checking: "magnifyingglass"
        case .done: "checkmark.circle"
        case .cancelled: "xmark.circle"
        }
    }

    private var statsLabel: String {
        switch phase {
        case .crawling:
            let pps = pagesPerSecond > 0 ? String(format: " | %.1f pg/s", pagesPerSecond) : ""
            return "\(pagesVisited)/\(maxPages) pages | \(domainCount) domains | depth \(currentDepth)\(pps)"
        case .checking:
            return "\(domainsChecked)/\(domainsToCheck) checked"
        case .seeding:
            return statusMessage
        default:
            return ""
        }
    }
}

// MARK: - Activity Row

struct ActivityRow: View {
    let entry: ActivityEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)
            Text(Self.timeFormatter.string(from: entry.date))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.quaternary)
            Text(entry.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var dotColor: Color {
        switch entry.type {
        case .seeding: Color.npAccent
        case .crawl: Color.npAccent.opacity(0.6)
        case .domain: Color.npGreen
        case .check: Color.npGreen.opacity(0.7)
        case .info: .secondary
        }
    }
}
