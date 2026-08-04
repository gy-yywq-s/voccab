// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VocabKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VocabKit", targets: ["VocabKit"])
    ],
    targets: [
        .target(name: "VocabKit"),
        .testTarget(name: "VocabKitTests", dependencies: ["VocabKit"]),
    ]
)
