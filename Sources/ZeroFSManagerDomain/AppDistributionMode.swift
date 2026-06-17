import Foundation

public enum AppDistributionMode: String, Codable, Equatable, Sendable {
    case githubDev = "github-dev"
    case officialRelease = "official-release"

    public static let environmentKey = "ZEROFS_MANAGER_DISTRIBUTION_MODE"
    public static let defaultMode: AppDistributionMode = .githubDev

    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppDistributionMode {
        guard let rawValue = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return defaultMode
        }
        return AppDistributionMode(rawValue: rawValue) ?? defaultMode
    }

    public var title: String {
        switch self {
        case .githubDev:
            "GitHub-style development build"
        case .officialRelease:
            "Official Developer ID release"
        }
    }

    public var warningText: String {
        switch self {
        case .githubDev:
            "Current build is a GitHub-style development build and is not signed with Apple Developer ID. It is suitable for development testing and technical users running manual workflows; it does not represent the official macOS distribution experience."
        case .officialRelease:
            "Official release mode expects Developer ID signing, hardened runtime, notarization, stapling, and the formal SMAppService helper registration path."
        }
    }

    public var allowsAutomaticHelperRegistration: Bool {
        self == .officialRelease
    }

    public var allowsLoginAutoMount: Bool {
        self == .officialRelease
    }

    public var requiresAppleTeamIdentifier: Bool {
        self == .officialRelease
    }

    public var helperRegistrationUnavailableMessage: String {
        switch self {
        case .githubDev:
            "Current build is GitHub-style development mode, so the Apple official helper authorization path is disabled. Use the manual CLI or debug launchd path to test real S3 mounts; formal helper authorization will be enabled after Developer ID signing and notarization."
        case .officialRelease:
            "Official release helper registration is unavailable. Verify Developer ID signing, notarization, and Login Items approval."
        }
    }
}
