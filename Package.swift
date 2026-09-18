// swift-tools-version: 6.0
import PackageDescription

// Swift Package Manager instead of an Xcode project: one command builds everything,
// there is no .xcodeproj drifting apart with every tool run, and a dependency would be
// one line.
//
// AnyPlayKit holds the logic that can be tested without a window server. The app
// target holds everything that needs one.
//
// Swift 5 language mode because Swift 6's strict concurrency checking demands special
// treatment at every corner of AppKit code without making anything here safer.
let package = Package(
    name: "AnyPlay",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "AnyPlayKit",
            path: "Sources/AnyPlayKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "AnyPlay",
            dependencies: ["AnyPlayKit"],
            path: "Sources/AnyPlay",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AnyPlayKitTests",
            dependencies: ["AnyPlayKit"],
            path: "Tests/AnyPlayKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
