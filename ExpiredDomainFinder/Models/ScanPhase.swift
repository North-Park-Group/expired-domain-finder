import Foundation

enum ScanPhase: Equatable {
    case idle
    case seeding
    case crawling
    case checking
    case done
    case cancelled
}
