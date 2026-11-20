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
            path: "Sources/TouchRedirect",
            // Icons are packaged by Scripts/build-app.sh; excluding them lets the
            // package build with Command Line Tools only (no actool/Xcode needed).
            exclude: ["Resources", "Info.plist"]
        )
    ]
)
