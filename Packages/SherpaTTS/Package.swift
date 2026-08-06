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
        .binaryTarget(
            name: "onnxruntime",
            url: "https://github.com/willwade/sherpa-onnx-spm/releases/download/\(version)/onnxruntime.xcframework.zip",
            checksum: "6d8fb92fab1c71be12d2f000df7ee4d29709be20aa9bd7f4d303bae10bd25415"
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
