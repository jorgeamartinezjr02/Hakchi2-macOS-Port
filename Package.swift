// swift-tools-version:5.9
import PackageDescription

// Homebrew paths for Apple Silicon and Intel Macs
let brewPrefix = "/opt/homebrew"    // Apple Silicon
let brewPrefixIntel = "/usr/local"  // Intel

let package = Package(
    name: "Hakchi",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Hakchi", targets: ["Hakchi"])
    ],
    dependencies: [],
    targets: [
        .systemLibrary(
            name: "CLibUSB",
            pkgConfig: "libusb-1.0",
            providers: [
                .brew(["libusb"])
            ]
        ),
        .systemLibrary(
            name: "CLibSSH2",
            pkgConfig: "libssh2",
            providers: [
                .brew(["libssh2"])
            ]
        ),
        .executableTarget(
            name: "Hakchi",
            dependencies: ["CLibUSB", "CLibSSH2"],
            path: "Sources/Hakchi",
            resources: [
                .copy("../../Resources/game_db.json")
            ],
            cSettings: [
                .unsafeFlags([
                    "-I\(brewPrefix)/include",
                    "-I\(brewPrefixIntel)/include",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(brewPrefix)/lib",
                    "-L\(brewPrefixIntel)/lib",
                ]),
            ]
        ),
        .testTarget(
            name: "HakchiTests",
            dependencies: ["Hakchi"],
            path: "Tests/HakchiTests"
        )
    ]
)
