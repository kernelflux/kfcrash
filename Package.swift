// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KFCrash",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "KFCrash",
            targets: ["KFCrash"]
        ),
        .library(
            name: "KFCReporting",
            targets: ["KFCReporting"]
        ),
        .library(
            name: "KFCAPI",
            targets: ["KFCAPI"]
        ),
        .library(
            name: "KFCSwift",
            targets: ["KFCSwift"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/kernelflux/kfservice.git", from: "1.0.0"),
    ],
    targets: [
        // C/C++ core (Core + RecordingCore merged)
        .target(
            name: "KFCCore",
            path: "Sources/KFCCore",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .define("NDEBUG", .when(configuration: .release)),
            ],
            cxxSettings: [
                .headerSearchPath("."),
            ],
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("c++"),
            ]
        ),

        // ObjC wrapper (Recording — KFCrash.h, KFCrashConfiguration, monitors)
        .target(
            name: "KFCrash",
            dependencies: ["KFCCore"],
            path: "Sources/KFCrash",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("Monitors"),
            ],
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("Monitors"),
            ],
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("c++"),
            ]
        ),

        // Reporting (Filters + Sinks + Installations merged)
        .target(
            name: "KFCReporting",
            dependencies: ["KFCrash"],
            path: "Sources/KFCReporting",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
            ],
            linkerSettings: [
                .linkedLibrary("z"),
            ]
        ),

        // Protocol-only API (zero dependency)
        .target(
            name: "KFCAPI",
            path: "Sources/KFCAPI"
        ),

        // Swift wrapper + Registration
        .target(
            name: "KFCSwift",
            dependencies: [
                "KFCrash",
                "KFCAPI",
                .product(name: "KFService", package: "KFService"),
            ],
            path: "Sources/KFCSwift"
        ),
    ],
    cxxLanguageStandard: .gnucxx11
)
