import Foundation

enum ActivityType {
    case seeding
    case crawl
    case domain
    case check
    case info
}

struct ActivityEntry: Identifiable {
    let id = UUID()
    let date: Date
    let message: String
    let type: ActivityType
}
