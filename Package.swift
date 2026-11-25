// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProjecaoRenda",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ProjecaoRenda", targets: ["ProjecaoRenda"])],
    targets: [
        .executableTarget(name: "ProjecaoRenda"),
        .testTarget(name: "ProjecaoRendaTests", dependencies: ["ProjecaoRenda"])
    ]
)
