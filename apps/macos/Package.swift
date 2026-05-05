// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Phonos",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Phonos", targets: ["Phonos"])
    ],
    dependencies: [
        .package(path: "Packages/KeyboardShortcuts"),
    ],
    targets: [
        .executableTarget(
            name: "Phonos",
            dependencies: ["KeyboardShortcuts"],
            path: "Sources"
        )
    ]
)
