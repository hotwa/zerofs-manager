import Foundation

public struct ProfileRuntimePaths: Equatable, Sendable {
    public let profileID: ProfileID
    public let runtimeRoot: String
    public let configPath: String
    public let envPath: String
    public let cachePath: String
    public let logPath: String
    public let runScriptPath: String
    public let mountScriptPath: String
    public let flushScriptPath: String
    public let runtimeLaunchDaemonPath: String
    public let mountLaunchDaemonPath: String
    public let reportDirectory: String

    public init(
        profile: MountProfile,
        baseRoot: String = "/Library/Application Support/ZeroFSManager/Profiles",
        launchDaemonRoot: String = "/Library/LaunchDaemons",
        logRoot: String = "/Library/Logs/ZeroFSManager"
    ) {
        self.profileID = profile.id
        self.runtimeRoot = "\(baseRoot)/\(profile.id.rawValue)"
        self.configPath = "\(runtimeRoot)/zerofs.toml"
        self.envPath = "\(runtimeRoot)/zerofs.env"
        self.cachePath = "/var/cache/zerofs-manager/\(profile.id.rawValue)"
        self.logPath = "\(logRoot)/\(profile.id.rawValue)/zerofs.log"
        self.runScriptPath = "\(runtimeRoot)/run-zerofs.sh"
        self.mountScriptPath = "\(runtimeRoot)/mount-zerofs.sh"
        self.flushScriptPath = "\(runtimeRoot)/flush-zerofs.sh"
        self.runtimeLaunchDaemonPath = "\(launchDaemonRoot)/com.zerofs.manager.profile.\(profile.id.rawValue).zerofs.plist"
        self.mountLaunchDaemonPath = "\(launchDaemonRoot)/com.zerofs.manager.profile.\(profile.id.rawValue).mount.plist"
        self.reportDirectory = "~/Library/Application Support/ZeroFSManager/Reports/\(profile.id.rawValue)"
    }
}

public struct ServiceNames: Equatable, Sendable {
    public let profileID: ProfileID
    public let helperLaunchDaemonLabel: String
    public let helperMachServiceName: String
    public let helperLaunchDaemonPlistName: String
    public let profileRuntimeLabel: String
    public let profileRuntimePlistName: String
    public let profileMountLabel: String

    public init(profile: MountProfile, bundleIdentifier: String = "com.zerofs.manager") {
        self.profileID = profile.id
        self.helperLaunchDaemonLabel = "\(bundleIdentifier).helper"
        self.helperMachServiceName = "\(bundleIdentifier).helper"
        self.helperLaunchDaemonPlistName = "\(helperLaunchDaemonLabel).plist"
        self.profileRuntimeLabel = "\(bundleIdentifier).profile.\(profile.id.rawValue).zerofs"
        self.profileRuntimePlistName = "\(profileRuntimeLabel).plist"
        self.profileMountLabel = "\(bundleIdentifier).profile.\(profile.id.rawValue).mount"
    }
}
