// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "AgentUsageBar",
    platforms: [.macOS(.v13)],
    targets: [.executableTarget(name: "AgentUsageBar", path: "Sources/AgentUsageBar")]
)
