import Foundation

public enum ValidationIssue: String, Codable, Equatable, Sendable, CustomStringConvertible {
    case invalidProfileID
    case invalidEndpoint
    case invalidRegion
    case invalidBucket
    case invalidPrefix
    case invalidMountPath
    case unsafeMountPath
    case invalidQuota
    case invalidCache
    case invalidPort
    case duplicatePorts

    public var description: String {
        rawValue
    }
}

public enum ProfileValidator {
    public static func validate(_ profile: MountProfile) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if !ProfileID.isValid(profile.id.rawValue) {
            issues.append(.invalidProfileID)
        }
        if !isValidEndpoint(profile.endpoint) {
            issues.append(.invalidEndpoint)
        }
        if !isValidRegion(profile.region) {
            issues.append(.invalidRegion)
        }
        if !isValidBucket(profile.bucket) {
            issues.append(.invalidBucket)
        }
        if !isValidPrefix(profile.prefix) {
            issues.append(.invalidPrefix)
        }
        issues.append(contentsOf: mountPathIssues(profile.mountPath))
        if profile.quota.gigabytes <= 0 {
            issues.append(.invalidQuota)
        }
        if profile.cache.diskGigabytes < 0 || profile.cache.memoryGigabytes < 0 {
            issues.append(.invalidCache)
        }
        if profile.ports.values.contains(where: { $0 < 1 || $0 > 65_535 }) {
            issues.append(.invalidPort)
        }
        if Set(profile.ports.values).count != profile.ports.values.count {
            issues.append(.duplicatePorts)
        }

        return Array(Set(issues)).sorted { $0.rawValue < $1.rawValue }
    }

    private static func isValidEndpoint(_ value: String) -> Bool {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            return false
        }
        return true
    }

    private static func isValidBucket(_ value: String) -> Bool {
        let pattern = /^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$/
        return value.wholeMatch(of: pattern) != nil && !value.contains("..")
    }

    private static func isValidRegion(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == value, !value.isEmpty else {
            return false
        }
        let pattern = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/
        return value.wholeMatch(of: pattern) != nil
    }

    private static func isValidPrefix(_ value: String) -> Bool {
        if value.isEmpty { return true }
        if value.hasPrefix("/") { return false }
        if value.contains("..") { return false }
        let pattern = /^[A-Za-z0-9._-]+(\/[A-Za-z0-9._-]+)*$/
        return value.wholeMatch(of: pattern) != nil
    }

    private static func mountPathIssues(_ path: MountPath) -> [ValidationIssue] {
        let raw = path.rawValue
        guard raw.hasPrefix("/") else {
            return [.invalidMountPath]
        }

        if raw.split(separator: "/").contains("..") {
            return [.unsafeMountPath]
        }

        let standardized = URL(fileURLWithPath: raw).standardizedFileURL.path
        if standardized != raw {
            return [.unsafeMountPath]
        }

        return []
    }
}

public enum OneActiveProfilePolicy {
    public static func canAdd(_ profile: MountProfile, to existing: [MountProfile]) -> Bool {
        existing.isEmpty || existing.contains(where: { $0.id == profile.id })
    }
}

public struct PrivilegedMountPathPolicy: Sendable {
    public var allowedRootPrefixes: [String]

    public init(allowedRootPrefixes: [String] = ["/Volumes/"]) {
        self.allowedRootPrefixes = allowedRootPrefixes
    }

    public func issues(for mountPath: MountPath) -> [ValidationIssue] {
        let baseIssues = ProfileValidator.validate(
            MountProfile(
                id: (try? ProfileID("path-check")) ?? ProfileID(rawValue: "path-check"),
                displayName: "Path Check",
                endpoint: "https://example.com",
                bucket: "example-bucket",
                prefix: "",
                mountPath: mountPath,
                quota: Quota(gigabytes: 1),
                cache: CacheSettings(diskGigabytes: 0, memoryGigabytes: 0),
                ports: PortSet(nfs: 2049, rpc: 17000, metrics: 9091),
                autoMount: .disabled,
                performanceTestSize: .megabytes(1)
            )
        ).filter { [.invalidMountPath, .unsafeMountPath].contains($0) }
        if !baseIssues.isEmpty {
            return baseIssues
        }

        let path = URL(fileURLWithPath: mountPath.rawValue).standardizedFileURL.path
        guard allowedRootPrefixes.contains(where: { prefix in
            path != prefix.dropLastSlash && path.hasPrefix(prefix)
        }) else {
            return [.unsafeMountPath]
        }
        return []
    }
}

private extension String {
    var dropLastSlash: String {
        hasSuffix("/") ? String(dropLast()) : self
    }
}
