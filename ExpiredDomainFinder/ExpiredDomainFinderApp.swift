import SwiftUI

@main
struct ExpiredDomainFinderApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .defaultSize(width: 900, height: 650)
        .windowStyle(.titleBar)
    }
}
