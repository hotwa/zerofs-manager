import Foundation

public struct ProfileID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) throws {
        guard Self.isValid(rawValue) else {
            throw ProfileIDError.invalid(rawValue)
        }
        self.rawValue = rawValue
    }

    public static func isValid(_ rawValue: String) -> Bool {
        let pattern = /^[a-z0-9][a-z0-9-]{0,62}$/
        return rawValue.wholeMatch(of: pattern) != nil
    }
}

public enum ProfileIDError: Error, Equatable, CustomStringConvertible {
    case invalid(String)

    public var description: String {
        switch self {
        case .invalid(let value):
            "Invalid profile ID: \(value)"
        }
    }
}

public struct MountPath: Codable, Hashable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func defaultPath(displayName: String) -> MountPath {
        let cleaned = displayName
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "-")
        let suffix = cleaned.isEmpty ? "Profile" : cleaned
        return MountPath(rawValue: "/Volumes/ZeroFS-\(suffix)")
    }
}

public struct Quota: Codable, Equatable, Sendable {
    public var gigabytes: Double

    public init(gigabytes: Double) {
        self.gigabytes = gigabytes
    }
}

public struct CacheSettings: Codable, Equatable, Sendable {
    public var diskGigabytes: Double
    public var memoryGigabytes: Double

    public init(diskGigabytes: Double, memoryGigabytes: Double) {
        self.diskGigabytes = diskGigabytes
        self.memoryGigabytes = memoryGigabytes
    }
}

public struct PortSet: Codable, Equatable, Sendable {
    public var nfs: Int
    public var rpc: Int
    public var metrics: Int

    public init(nfs: Int, rpc: Int, metrics: Int) {
        self.nfs = nfs
        self.rpc = rpc
        self.metrics = metrics
    }

    public var values: [Int] {
        [nfs, rpc, metrics]
    }
}

public enum AutoMountPolicy: String, Codable, Equatable, Sendable {
    case disabled
    case afterLogin
}

public enum PerformanceTestSize: Codable, Equatable, Sendable {
    case megabytes(Int)

    public var bytes: Int64 {
        switch self {
        case .megabytes(let value):
            Int64(value) * 1_048_576
        }
    }
}

public struct MountProfile: Codable, Equatable, Sendable {
    public var id: ProfileID
    public var displayName: String
    public var endpoint: String
    public var bucket: String
    public var prefix: String
    public var mountPath: MountPath
    public var quota: Quota
    public var cache: CacheSettings
    public var ports: PortSet
    public var autoMount: AutoMountPolicy
    public var performanceTestSize: PerformanceTestSize

    public init(
        id: ProfileID,
        displayName: String,
        endpoint: String,
        bucket: String,
        prefix: String,
        mountPath: MountPath,
        quota: Quota,
        cache: CacheSettings,
        ports: PortSet,
        autoMount: AutoMountPolicy,
        performanceTestSize: PerformanceTestSize
    ) {
        self.id = id
        self.displayName = displayName
        self.endpoint = endpoint
        self.bucket = bucket
        self.prefix = prefix
        self.mountPath = mountPath
        self.quota = quota
        self.cache = cache
        self.ports = ports
        self.autoMount = autoMount
        self.performanceTestSize = performanceTestSize
    }
}
