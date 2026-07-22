// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WriterFlow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WriterFlow", targets: ["WriterFlow"])
    ],
    dependencies: [
        // Vendored, SQLCipher-patched GRDB v7 (Stage 5.3's feasibility spike passed —
        // see phases/phase-5-v2-cloud-foundation.md and vendor/GRDB.swift/Package.swift's
        // own comments for why this is vendored rather than the plain remote v6 dependency
        // this used to be, and how to re-apply the patch on a future version bump).
        .package(path: "vendor/GRDB.swift")
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
