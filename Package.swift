// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ScreenRecorderApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ScreenRecorderApp", targets: ["ScreenRecorderApp"])
    ],
    targets: [
        .executableTarget(
            name: "ScreenRecorderApp",
            path: "Sources/ScreenRecorderApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("ImageIO"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
