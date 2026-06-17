// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ZeroFSManager",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ZeroFSManagerApp", targets: ["ZeroFSManagerApp"]),
        .executable(name: "ZeroFSPrivilegedHelper", targets: ["ZeroFSPrivilegedHelper"]),
        .library(name: "ZeroFSManagerDomain", targets: ["ZeroFSManagerDomain"]),
        .library(name: "ZeroFSManagerSecrets", targets: ["ZeroFSManagerSecrets"]),
        .library(name: "ZeroFSManagerHelperClient", targets: ["ZeroFSManagerHelperClient"]),
        .library(name: "ZeroFSLaunchd", targets: ["ZeroFSLaunchd"]),
        .library(name: "ZeroFSPerformance", targets: ["ZeroFSPerformance"]),
        .library(name: "ZeroFSPackagingSupport", targets: ["ZeroFSPackagingSupport"]),
        .library(name: "ZeroFSPrivilegedHelperCore", targets: ["ZeroFSPrivilegedHelperCore"]),
        .library(name: "ZeroFSProbeToolCore", targets: ["ZeroFSProbeToolCore"]),
        .executable(name: "ZeroFSProbeTool", targets: ["ZeroFSProbeTool"]),
        .executable(name: "ZeroFSProbeTests", targets: ["ZeroFSProbeTests"]),
        .executable(name: "ZeroFSManagerChecks", targets: ["ZeroFSManagerChecks"])
    ],
    targets: [
        .executableTarget(
            name: "ZeroFSManagerApp",
            dependencies: ["ZeroFSManagerUI"],
            path: "Sources/ZeroFSManagerApp"
        ),
        .target(
            name: "ZeroFSManagerUI",
            dependencies: [
                "ZeroFSManagerDomain",
                "ZeroFSManagerSecrets",
                "ZeroFSManagerHelperClient",
                "ZeroFSPerformance"
            ],
            path: "Sources/ZeroFSManagerUI"
        ),
        .target(
            name: "ZeroFSManagerDomain",
            path: "Sources/ZeroFSManagerDomain"
        ),
        .target(
            name: "ZeroFSManagerSecrets",
            dependencies: ["ZeroFSManagerDomain"],
            path: "Sources/ZeroFSManagerSecrets",
            linkerSettings: [.linkedFramework("Security")]
        ),
        .target(
            name: "ZeroFSManagerHelperClient",
            dependencies: ["ZeroFSManagerDomain"],
            path: "Sources/ZeroFSManagerHelperClient"
        ),
        .executableTarget(
            name: "ZeroFSPrivilegedHelper",
            dependencies: [
                "ZeroFSManagerDomain",
                "ZeroFSManagerHelperClient",
                "ZeroFSLaunchd",
                "ZeroFSPrivilegedHelperCore"
            ],
            path: "Sources/ZeroFSPrivilegedHelper"
        ),
        .target(
            name: "ZeroFSPrivilegedHelperCore",
            dependencies: [
                "ZeroFSManagerDomain",
                "ZeroFSManagerHelperClient"
            ],
            path: "Sources/ZeroFSPrivilegedHelperCore"
        ),
        .target(
            name: "ZeroFSLaunchd",
            dependencies: ["ZeroFSManagerDomain"],
            path: "Sources/ZeroFSLaunchd"
        ),
        .target(
            name: "ZeroFSPerformance",
            dependencies: [
                "ZeroFSManagerDomain",
                "ZeroFSManagerHelperClient"
            ],
            path: "Sources/ZeroFSPerformance"
        ),
        .target(
            name: "ZeroFSPackagingSupport",
            dependencies: ["ZeroFSManagerDomain"],
            path: "Sources/ZeroFSPackagingSupport"
        ),
        .executableTarget(
            name: "ZeroFSProbeTool",
            dependencies: [
                "ZeroFSProbeToolCore",
                "ZeroFSManagerDomain",
                "ZeroFSPerformance"
            ],
            path: "Sources/ZeroFSProbeTool"
        ),
        .target(
            name: "ZeroFSProbeToolCore",
            dependencies: [
                "ZeroFSManagerDomain",
                "ZeroFSPerformance"
            ],
            path: "Sources/ZeroFSProbeToolCore"
        ),
        .executableTarget(
            name: "ZeroFSManagerChecks",
            dependencies: [
                "ZeroFSManagerDomain",
                "ZeroFSManagerSecrets",
                "ZeroFSManagerHelperClient",
                "ZeroFSLaunchd",
                "ZeroFSPerformance",
                "ZeroFSPackagingSupport",
                "ZeroFSPrivilegedHelperCore"
            ],
            path: "Sources/ZeroFSManagerChecks"
        ),
        .executableTarget(
            name: "ZeroFSProbeTests",
            dependencies: [
                "ZeroFSManagerDomain",
                "ZeroFSPerformance",
                "ZeroFSProbeToolCore"
            ],
            path: "Sources/ZeroFSProbeTests"
        ),
        .testTarget(
            name: "ZeroFSProbeXCTests",
            dependencies: [
                "ZeroFSManagerDomain",
                "ZeroFSPerformance",
                "ZeroFSProbeToolCore"
            ],
            path: "Tests/ZeroFSProbeXCTests"
        ),
        .testTarget(
            name: "ZeroFSManagerUIXCTests",
            dependencies: [
                "ZeroFSManagerDomain",
                "ZeroFSPerformance",
                "ZeroFSManagerUI"
            ],
            path: "Tests/ZeroFSManagerUIXCTests"
        )
    ]
)
