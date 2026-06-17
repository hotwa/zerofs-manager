import Foundation

public enum DistributionMode: String, Codable, Equatable, Sendable {
    case githubDev = "github-dev"
    case officialRelease = "official-release"

    public var requiresNotarization: Bool {
        self == .officialRelease
    }
}

public struct AppBundleLayout: Equatable, Sendable {
    public var appName: String
    public var bundleIdentifier: String
    public var helperBundleProgram: String

    public init(
        appName: String = "ZeroFS Manager",
        bundleIdentifier: String = "com.zerofs.manager",
        helperBundleProgram: String = "Contents/MacOS/ZeroFSPrivilegedHelper"
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.helperBundleProgram = helperBundleProgram
    }

    public var appBundleName: String {
        "\(appName).app"
    }

    public var executablePath: String {
        "Contents/MacOS/ZeroFSManagerApp"
    }

    public var helperExecutablePath: String {
        helperBundleProgram
    }

    public var infoPlistPath: String {
        "Contents/Info.plist"
    }

    public var embedsZeroFSBinary: Bool {
        false
    }

    public var externalDependencyName: String {
        "zerofs"
    }

    public var launchDaemonPlistPath: String {
        "Contents/Library/LaunchDaemons/\(bundleIdentifier).helper.plist"
    }

    public var dmgVolumeName: String {
        appName
    }
}
