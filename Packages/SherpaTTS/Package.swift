// swift-tools-version: 5.9
import PackageDescription

// sherpa-onnx ships its iOS/macOS binaries as xcframeworks rather than
// source. Both archives are pinned by checksum, so the exact bytes
// verified when this package was written are the only ones that can be
// fetched. The Swift wrapper shipped alongside them upstream is declared
// internal, so PiperVoice.swift below is our own public wrapper over the
// C API the xcframework exposes as the `sherpa_onnx` module.
let version = "1.13.3"

let package = Package(
    name: "SherpaTTS",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SherpaTTS", targets: ["SherpaTTS"]),
    ],
    targets: [
        .binaryTarget(
            name: "sherpa-onnx",
            url: "https://github.com/willwade/sherpa-onnx-spm/releases/download/\(version)/sherpa-onnx.xcframework.zip",
            checksum: "edf529802f437ff1d04057380fffb4151c092fc2cc71f00d17a01c2953887b6d"
        ),
        // Same 1.13.3 runtime, repackaged without its headers: Xcode copies
        // every binary target's headers into one `include/` directory, and
        // two frameworks shipping `module.modulemap` fail the build. Nothing
        // here imports onnxruntime — only sherpa-onnx's C API — so dropping
        // them costs nothing. The repack is byte-reproducible.
        .binaryTarget(
            name: "onnxruntime",
            url: "https://voccab-res.gaelis.cc/resources/onnxruntime-slim.xcframework.zip",
            checksum: "c9c7781ff70d37df1bf0799fddf3a08920bc12c526bb1ea32ae5994ad0ad1fe5"
        ),
        .target(
            name: "SherpaTTS",
            dependencies: ["sherpa-onnx", "onnxruntime"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
            ]
        ),
    ]
)
