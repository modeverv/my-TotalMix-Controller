// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TotalMixSnapshotTouch",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "TotalMixSnapshotTouch", targets: ["TotalMixSnapshotTouch"])],
    targets: [
        .executableTarget(name: "TotalMixSnapshotTouch"),
        .testTarget(name: "TotalMixSnapshotTouchTests", dependencies: ["TotalMixSnapshotTouch"])
    ]
)
