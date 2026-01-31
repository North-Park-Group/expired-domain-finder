import Foundation

struct DomainResult: Identifiable, Hashable {
    let id = UUID()
    let domain: String
    let linkCount: Int
    let foundOn: [String]

    var foundOnDisplay: String {
        foundOn.joined(separator: " | ")
    }
}
