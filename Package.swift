// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SKOverlayPrefetch",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "SKOverlayPrefetch", targets: ["SKOverlayPrefetch"]),
    ],
    targets: [
        .target(name: "SKOverlayPrefetch", path: "SKOverlayPrefetch"),
    ]
)
