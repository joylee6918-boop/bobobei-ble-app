// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BobobeiBLE",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "BobobeiBLE", targets: ["BobobeiBLE"])
    ],
    targets: [
        .target(name: "BobobeiBLE"),
        .testTarget(name: "BobobeiBLETests", dependencies: ["BobobeiBLE"])
    ]
)
