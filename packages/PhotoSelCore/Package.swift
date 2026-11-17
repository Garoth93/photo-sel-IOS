// swift-tools-version: 5.9
// Logic package for the photoSel iPad app. Pure Swift (Foundation only), no
// UIKit/SwiftUI/ImageIO: it must build and test on Linux with `swift test`.
import PackageDescription

let package = Package(
    name: "PhotoSelCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PhotoSelCore", targets: ["PhotoSelCore"])
    ],
    targets: [
        .target(
            name: "PhotoSelCore",
            path: "Sources/PhotoSelCore"
        ),
        .testTarget(
            name: "PhotoSelCoreTests",
            dependencies: ["PhotoSelCore"],
            path: "Tests/PhotoSelCoreTests"
        )
    ]
)
