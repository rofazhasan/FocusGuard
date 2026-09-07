// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FocusGuard",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "FocusGuardCore",
            targets: ["FocusGuardCore"]
        ),
        .executable(
            name: "FocusGuardApp",
            targets: ["FocusGuardApp"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FocusGuardCore",
            dependencies: [],
            path: "FocusGuardCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "FocusGuardApp",
            dependencies: ["FocusGuardCore"],
            path: "FocusGuardApp"
        ),
        .executableTarget(
            name: "FocusGuardVerificationRunner",
            dependencies: ["FocusGuardCore"],
            path: "FocusGuardVerification"
        ),
        .executableTarget(
            name: "FocusGuardAdversarialRunner",
            dependencies: ["FocusGuardCore"],
            path: "FocusGuardAdversarial"
        )
    ]
)
