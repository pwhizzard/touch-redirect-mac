// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TouchRedirect",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "TouchRedirect",
            path: "Sources/TouchRedirect"
        )
    ]
)
