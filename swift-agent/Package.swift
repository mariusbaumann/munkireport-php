// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "munkireport-runner",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "munkireport-runner",
            dependencies: ["MunkiReportLib"],
            path: "Sources/munkireport-runner"
        ),
        .target(
            name: "MunkiReportLib",
            path: "Sources/MunkiReportLib"
        ),
        .testTarget(
            name: "MunkiReportLibTests",
            dependencies: ["MunkiReportLib"],
            path: "Tests/MunkiReportLibTests"
        ),
    ]
)
