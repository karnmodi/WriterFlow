// swift-tools-version:6.1
import PackageDescription

// Stage 5.3 SQLCipher feasibility spike (phases/phase-5-v2-cloud-foundation.md).
// Deliberately an isolated package, not part of the main WriterFlow app target:
// GRDB v7 (vendored, ../../vendor/GRDB.swift) and the main app's GRDB v6 dependency
// both export a module literally named `GRDB` — they cannot be linked into the same
// target. This spike only answers "does SPM + GRDB + SQLCipher build and produce a
// real encrypted database on macOS" before any production migration is attempted.
let package = Package(
    name: "SQLCipherFeasibilitySpike",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../vendor/GRDB.swift")
    ],
    targets: [
        .executableTarget(
            name: "SQLCipherFeasibilitySpike",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        )
    ]
)
