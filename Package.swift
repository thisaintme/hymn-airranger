// swift-tools-version: 5.9
import PackageDescription

var targets: [Target] = [
    .target(name: "HymnCore"),
    .executableTarget(name: "HymnCLI", dependencies: ["HymnCore"]),
    .testTarget(name: "HymnCoreTests", dependencies: ["HymnCore"])
]
var products: [Product] = [
    .library(name: "HymnCore", targets: ["HymnCore"]),
    .executable(name: "hymn-cli", targets: ["HymnCLI"])
]
#if os(macOS)
targets.append(.executableTarget(name: "HymnAIrranger", dependencies: ["HymnCore"], resources: [.copy("Resources/Web")]))
products.append(.executable(name: "HymnAIrranger", targets: ["HymnAIrranger"]))
#endif
let package = Package(name: "HymnAIrranger", platforms: [.macOS(.v14)], products: products, targets: targets)
