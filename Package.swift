// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyTerm",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MyTerm", targets: ["MyTerm"])],
    dependencies: [.package(path: "vendor/SwiftTerm")],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .systemLibrary(name: "CIconv"),
        .systemLibrary(name: "CCommonCrypto"),
        .target(name: "MyTermCore", dependencies: ["CSQLite", "CIconv", "CCommonCrypto"]),
        .executableTarget(name: "MyTermProxy"),
        .executableTarget(name: "MyTerm", dependencies: ["MyTermCore", "SwiftTerm"]),
        .executableTarget(name: "MyTermChecks", dependencies: ["MyTermCore", "SwiftTerm"], path: "Tests/MyTermCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
