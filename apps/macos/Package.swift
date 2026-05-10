// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Phonos",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Phonos", targets: ["Phonos"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.3"),
    ],
    targets: [
        .executableTarget(
            name: "Phonos",
            dependencies: ["KeyboardShortcuts", .product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources"
        ),
        .testTarget(
            name: "PhonosTests",
            dependencies: ["Phonos"],
            path: "Tests"
        )
    ]
)
