// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ExpiredDomainFinder",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "ExpiredDomainFinder",
            dependencies: ["SwiftSoup"],
            path: "ExpiredDomainFinder",
            exclude: ["ExpiredDomainFinder.entitlements"],
            resources: [
                .copy("Resources/public_suffix_list.dat"),
            ]
        ),
        .testTarget(
            name: "ExpiredDomainFinderTests",
            dependencies: ["ExpiredDomainFinder", "SwiftSoup"],
            path: "Tests"
        ),
    ]
)
