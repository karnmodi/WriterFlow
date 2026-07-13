// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WriterFlow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WriterFlow", targets: ["WriterFlow"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .executableTarget(
            name: "WriterFlow",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/WriterFlow",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "WriterFlowTests",
            dependencies: ["WriterFlow"],
            path: "Tests/WriterFlowTests"
        )
    ]
)
