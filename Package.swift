// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "recordo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Recordo", targets: ["Recordo"])
    ],
    targets: [
        .target(
            name: "RecordoKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Recordo",
            dependencies: ["RecordoKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "RecordoKitTests",
            dependencies: ["RecordoKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
