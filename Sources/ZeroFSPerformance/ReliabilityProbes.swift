import Foundation
import CryptoKit
import ZeroFSManagerDomain

#if canImport(Darwin)
import Darwin
#endif

public enum ProbeDefaults {
    public static let defaultIntervalSeconds = 3_600
    public static let defaultSizeBytes: Int64 = 4 * 1_048_576
    public static let scheduledMaxSizeBytes: Int64 = 16 * 1_048_576
    public static let manualMaxSizeBytesWithoutConfirmation: Int64 = 64 * 1_048_576
    public static let defaultRetentionCount = 500
    public static let defaultRetentionAgeSeconds: TimeInterval = 60 * 60 * 24 * 30
    public static let degradedThroughputBytesPerSecond: Double = 5 * 1_048_576
    public static let degradedOperationSeconds: TimeInterval = 60
}

public struct ProbeSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var intervalSeconds: Int
    public var sizeBytes: Int64
    public var backgroundLaunchDaemonEnabled: Bool

    public init(
        enabled: Bool = false,
        intervalSeconds: Int = ProbeDefaults.defaultIntervalSeconds,
        sizeBytes: Int64 = ProbeDefaults.defaultSizeBytes,
        backgroundLaunchDaemonEnabled: Bool = false
    ) {
        self.enabled = enabled
        self.intervalSeconds = intervalSeconds
        self.sizeBytes = sizeBytes
        self.backgroundLaunchDaemonEnabled = backgroundLaunchDaemonEnabled
    }
}

public enum ProbeTrigger: String, Codable, Equatable, Sendable {
    case manual
    case inAppSchedule
    case backgroundLaunchDaemon
}

public enum ProbeOutcome: String, Codable, Equatable, Sendable {
    case success
    case degraded
    case failed
    case skipped
}

public enum ReliabilityClassification: String, Codable, Equatable, Sendable {
    case disabled
    case unknown
    case healthy
    case degraded
    case failed
}

public struct ProbeResult: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var profileID: ProfileID
    public var trigger: ProbeTrigger
    public var outcome: ProbeOutcome
    public var startedAt: Date
    public var endedAt: Date
    public var sizeBytes: Int64
    public var writeSeconds: TimeInterval
    public var readSeconds: TimeInterval
    public var checksumStatus: ChecksumStatus
    public var remoteCleanup: CleanupStatus
    public var readbackCleanup: CleanupStatus
    public var dfBeforeWrite: DiskUsageSnapshot?
    public var dfAfterWrite: DiskUsageSnapshot?
    public var dfAfterCleanup: DiskUsageSnapshot?
    public var metricsSummary: String
    public var failureReason: String?

    public var durationSeconds: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    public var writeBytesPerSecond: Double? {
        Self.bytesPerSecond(sizeBytes: sizeBytes, seconds: writeSeconds)
    }

    public var readBytesPerSecond: Double? {
        Self.bytesPerSecond(sizeBytes: sizeBytes, seconds: readSeconds)
    }

    public init(
        id: UUID = UUID(),
        profileID: ProfileID,
        trigger: ProbeTrigger,
        outcome: ProbeOutcome,
        startedAt: Date,
        endedAt: Date,
        sizeBytes: Int64,
        writeSeconds: TimeInterval,
        readSeconds: TimeInterval,
        checksumStatus: ChecksumStatus,
        remoteCleanup: CleanupStatus,
        readbackCleanup: CleanupStatus,
        dfBeforeWrite: DiskUsageSnapshot?,
        dfAfterWrite: DiskUsageSnapshot?,
        dfAfterCleanup: DiskUsageSnapshot?,
        metricsSummary: String,
        failureReason: String?
    ) {
        self.id = id
        self.profileID = profileID
        self.trigger = trigger
        self.outcome = outcome
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sizeBytes = sizeBytes
        self.writeSeconds = writeSeconds
        self.readSeconds = readSeconds
        self.checksumStatus = checksumStatus
        self.remoteCleanup = remoteCleanup
        self.readbackCleanup = readbackCleanup
        self.dfBeforeWrite = dfBeforeWrite
        self.dfAfterWrite = dfAfterWrite
        self.dfAfterCleanup = dfAfterCleanup
        self.metricsSummary = metricsSummary
        self.failureReason = failureReason
    }

    private static func bytesPerSecond(sizeBytes: Int64, seconds: TimeInterval) -> Double? {
        guard sizeBytes > 0, seconds > 0 else { return nil }
        return Double(sizeBytes) / seconds
    }
}

public enum ReliabilityClassifier {
    public static func classification(
        settings: ProbeSettings,
        latestResult: ProbeResult?
    ) -> ReliabilityClassification {
        guard settings.enabled else { return .disabled }
        guard let latestResult else { return .unknown }

        if latestResult.outcome == .failed ||
            latestResult.checksumStatus == .fail ||
            latestResult.remoteCleanup.isFailure ||
            latestResult.readbackCleanup.isFailure {
            return .failed
        }

        if latestResult.outcome == .skipped {
            return .unknown
        }

        if latestResult.outcome == .degraded ||
            latestResult.isVerySlow {
            return .degraded
        }

        return .healthy
    }
}

public struct FileProbeSettingsStore {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> [ProfileID: ProbeSettings] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: fileURL)
        let rawSettings = try JSONDecoder().decode([String: ProbeSettings].self, from: data)
        return Dictionary(
            uniqueKeysWithValues: rawSettings.map { key, value in
                (ProfileID(rawValue: key), value)
            }
        )
    }

    public func save(_ settingsByProfile: [ProfileID: ProbeSettings]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let rawSettings = Dictionary(
            uniqueKeysWithValues: settingsByProfile.map { profileID, settings in
                (profileID.rawValue, settings)
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(rawSettings).write(to: fileURL, options: .atomic)
    }
}

public struct ProbeResultRetention: Equatable, Sendable {
    public var maxRecordsPerProfile: Int
    public var maxAgeSeconds: TimeInterval

    public init(
        maxRecordsPerProfile: Int = ProbeDefaults.defaultRetentionCount,
        maxAgeSeconds: TimeInterval = ProbeDefaults.defaultRetentionAgeSeconds
    ) {
        self.maxRecordsPerProfile = max(0, maxRecordsPerProfile)
        self.maxAgeSeconds = max(0, maxAgeSeconds)
    }
}

public struct FileProbeResultStore {
    public var directoryURL: URL
    public var retention: ProbeResultRetention

    public init(directoryURL: URL, retention: ProbeResultRetention = ProbeResultRetention()) {
        self.directoryURL = directoryURL
        self.retention = retention
    }

    public func fileURL(for profileID: ProfileID) -> URL {
        directoryURL.appendingPathComponent(sanitizedProfileFileName(profileID.rawValue), isDirectory: false)
    }

    public func append(_ result: ProbeResult) throws {
        var results = try read(profileID: result.profileID)
        results.append(result.sanitizedForStorage())
        try write(retained(results, now: Date()), for: result.profileID)
    }

    public func load(profileID: ProfileID) throws -> [ProbeResult] {
        let loaded = try read(profileID: profileID)
        let kept = retained(loaded, now: Date())
        if kept != loaded {
            try write(kept, for: profileID)
        }
        return kept
    }

    private func read(profileID: ProfileID) throws -> [ProbeResult] {
        let url = fileURL(for: profileID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ProbeResult].self, from: data)
    }

    private func write(_ results: [ProbeResult], for profileID: ProfileID) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(results.map { $0.sanitizedForStorage() })
            .write(to: fileURL(for: profileID), options: .atomic)
    }

    private func retained(_ results: [ProbeResult], now: Date) -> [ProbeResult] {
        let cutoff = now.addingTimeInterval(-retention.maxAgeSeconds)
        return results
            .map { $0.sanitizedForStorage() }
            .filter { retention.maxAgeSeconds == 0 ? $0.startedAt >= now : $0.startedAt >= cutoff }
            .sorted { lhs, rhs in
                if lhs.startedAt == rhs.startedAt {
                    return lhs.id.uuidString > rhs.id.uuidString
                }
                return lhs.startedAt > rhs.startedAt
            }
            .prefix(retention.maxRecordsPerProfile)
            .map { $0 }
    }
}

public protocol MountTableProvider {
    func mountOutput() -> String?
}

public struct SystemMountTableProvider: MountTableProvider {
    public init() {}

    public func mountOutput() -> String? {
        LocalMountTable.currentOutput()
    }
}

public struct StaticMountTableProvider: MountTableProvider {
    public var output: String

    public init(mountOutput: String) {
        self.output = mountOutput
    }

    public func mountOutput() -> String? {
        output
    }
}

public struct ProbeRunLock: Sendable {
    public var lockDirectory: URL
    public var staleAfterSeconds: TimeInterval

    public init(lockDirectory: URL, staleAfterSeconds: TimeInterval = 30 * 60) {
        self.lockDirectory = lockDirectory
        self.staleAfterSeconds = staleAfterSeconds
    }

    public func acquire(
        now: Date = Date(),
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) throws -> ProbeRunLockHandle? {
        try FileManager.default.createDirectory(
            at: lockDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            try createLock(processIdentifier: processIdentifier, startedAt: now)
            return ProbeRunLockHandle(lockDirectory: lockDirectory)
        } catch {
            guard FileManager.default.fileExists(atPath: lockDirectory.path) else {
                throw error
            }
            guard isStale(now: now) else {
                return nil
            }
            do {
                try FileManager.default.removeItem(at: lockDirectory)
                try createLock(processIdentifier: processIdentifier, startedAt: now)
                return ProbeRunLockHandle(lockDirectory: lockDirectory)
            } catch {
                return nil
            }
        }
    }

    private func createLock(processIdentifier: Int32, startedAt: Date) throws {
        try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockDirectory.path)
        let metadata = ProbeRunLockMetadata(pid: processIdentifier, startedAt: startedAt)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: metadataURL, options: .atomic)
    }

    private func isStale(now: Date) -> Bool {
        guard let metadata = try? readMetadata() else {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: lockDirectory.path),
                  let modifiedAt = attributes[.modificationDate] as? Date else {
                return true
            }
            return now.timeIntervalSince(modifiedAt) > staleAfterSeconds
        }
        if now.timeIntervalSince(metadata.startedAt) > staleAfterSeconds {
            return true
        }
        return !Self.processExists(metadata.pid)
    }

    private func readMetadata() throws -> ProbeRunLockMetadata {
        let data = try Data(contentsOf: metadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProbeRunLockMetadata.self, from: data)
    }

    private var metadataURL: URL {
        lockDirectory.appendingPathComponent("owner.json", isDirectory: false)
    }

    private static func processExists(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        #if canImport(Darwin)
        if Darwin.kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
        #else
        return true
        #endif
    }
}

public struct ProbeRunLockHandle: Sendable {
    public var lockDirectory: URL

    public init(lockDirectory: URL) {
        self.lockDirectory = lockDirectory
    }

    public func release() {
        try? FileManager.default.removeItem(at: lockDirectory)
    }
}

private struct ProbeRunLockMetadata: Codable {
    var pid: Int32
    var startedAt: Date
}

public struct RandomByteGenerator: ByteGenerator {
    public init() {}

    public func makeChunk(offset: Int64, size: Int) throws -> Data {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<size).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) }
        return Data(bytes)
    }
}

public struct ReliabilityProbeRunner {
    private let fileManager: FileManager
    private let helper: PerformanceHelper
    private let metrics: MetricsProvider
    private let diskUsage: DiskUsageProvider
    private let byteGenerator: ByteGenerator
    private let mountTable: MountTableProvider
    private let chunkSize: Int
    private let settleAfterCleanupNanoseconds: UInt64

    public init(
        fileManager: FileManager,
        helper: PerformanceHelper,
        metrics: MetricsProvider,
        diskUsage: DiskUsageProvider = FileManagerDiskUsageProvider(),
        byteGenerator: ByteGenerator = RandomByteGenerator(),
        mountTable: MountTableProvider = SystemMountTableProvider(),
        chunkSize: Int = 1_048_576,
        settleAfterCleanupNanoseconds: UInt64 = 250_000_000
    ) {
        self.fileManager = fileManager
        self.helper = helper
        self.metrics = metrics
        self.diskUsage = diskUsage
        self.byteGenerator = byteGenerator
        self.mountTable = mountTable
        self.chunkSize = chunkSize
        self.settleAfterCleanupNanoseconds = settleAfterCleanupNanoseconds
    }

    public func run(
        profileID: ProfileID,
        mountDirectory: URL,
        workDirectory: URL,
        sizeBytes: Int64,
        trigger: ProbeTrigger
    ) async -> ProbeResult {
        let id = UUID()
        let startedAt = Date()
        var endedAt = startedAt
        var writeSeconds: TimeInterval = 0
        var readSeconds: TimeInterval = 0
        var checksumStatus: ChecksumStatus = .fail
        var remoteCleanup: CleanupStatus = .notPresent
        var readbackCleanup: CleanupStatus = .notPresent
        var dfBeforeWrite: DiskUsageSnapshot?
        var dfAfterWrite: DiskUsageSnapshot?
        var dfAfterCleanup: DiskUsageSnapshot?
        var metricsSummary = ""
        var failureReason: String?
        var degradedReason: String?

        func result(outcome: ProbeOutcome) -> ProbeResult {
            ProbeResult(
                id: id,
                profileID: profileID,
                trigger: trigger,
                outcome: outcome,
                startedAt: startedAt,
                endedAt: endedAt,
                sizeBytes: sizeBytes,
                writeSeconds: writeSeconds,
                readSeconds: readSeconds,
                checksumStatus: checksumStatus,
                remoteCleanup: remoteCleanup,
                readbackCleanup: readbackCleanup,
                dfBeforeWrite: dfBeforeWrite,
                dfAfterWrite: dfAfterWrite,
                dfAfterCleanup: dfAfterCleanup,
                metricsSummary: metricsSummary,
                failureReason: failureReason ?? degradedReason
            ).sanitizedForStorage()
        }

        func finishFailure(_ reason: String) -> ProbeResult {
            failureReason = reason
            endedAt = Date()
            return result(outcome: .failed)
        }

        guard sizeBytes > 0 else {
            return finishFailure("invalid probe size: \(sizeBytes)")
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: mountDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return finishFailure("mount directory is not available: \(mountDirectory.path)")
        }

        guard let mountOutput = mountTable.mountOutput(),
              LocalMountTable.isMounted(path: mountDirectory.path, mountOutput: mountOutput) else {
            return finishFailure("mount path is not mounted as a local ZeroFS NFS filesystem")
        }

        let probeRoot = mountDirectory.appendingPathComponent(".zerofs-manager-probes", isDirectory: true)
        let probeDirectory = probeRoot.appendingPathComponent(profileID.rawValue, isDirectory: true)
        let remoteURL = probeDirectory.appendingPathComponent("\(id.uuidString).bin", isDirectory: false)
        let readbackURL = workDirectory.appendingPathComponent(
            "\(profileID.rawValue)-\(id.uuidString)-readback.bin",
            isDirectory: false
        )

        do {
            try fileManager.createDirectory(at: probeDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        } catch {
            return finishFailure("cannot create probe workspace: \(error.localizedDescription)")
        }

        do {
            dfBeforeWrite = try await diskUsage.snapshot(for: mountDirectory, phase: .beforeWrite)
        } catch {
            degradedReason = "df before write unavailable: \(error.localizedDescription)"
        }

        let expectedChecksum: ProbeDigest
        do {
            let writeStart = Date()
            expectedChecksum = try writeGeneratedData(to: remoteURL, sizeBytes: sizeBytes)
            writeSeconds = Date().timeIntervalSince(writeStart)
        } catch {
            remoteCleanup = cleanup(remoteURL)
            readbackCleanup = cleanup(readbackURL)
            cleanupEmptyProbeDirectories(probeDirectory: probeDirectory, probeRoot: probeRoot)
            return finishFailure("write failed: \(error.localizedDescription)")
        }

        #if canImport(Darwin)
        Darwin.sync()
        #endif

        do {
            dfAfterWrite = try await diskUsage.snapshot(for: mountDirectory, phase: .afterWrite)
        } catch {
            degradedReason = degradedReason ?? "df after write unavailable: \(error.localizedDescription)"
        }

        do {
            try await helper.flush(profileID: profileID)
        } catch {
            remoteCleanup = cleanup(remoteURL)
            readbackCleanup = cleanup(readbackURL)
            cleanupEmptyProbeDirectories(probeDirectory: probeDirectory, probeRoot: probeRoot)
            return finishFailure("flush failed: \(error.localizedDescription)")
        }

        let actualChecksum: ProbeDigest
        do {
            let readStart = Date()
            actualChecksum = try copyAndChecksum(from: remoteURL, to: readbackURL)
            readSeconds = Date().timeIntervalSince(readStart)
            checksumStatus = expectedChecksum == actualChecksum ? .pass : .fail
        } catch {
            remoteCleanup = cleanup(remoteURL)
            readbackCleanup = cleanup(readbackURL)
            cleanupEmptyProbeDirectories(probeDirectory: probeDirectory, probeRoot: probeRoot)
            return finishFailure("read failed: \(error.localizedDescription)")
        }

        do {
            metricsSummary = try await metrics.metrics()
        } catch {
            metricsSummary = "metrics unavailable: \(error.localizedDescription)"
            degradedReason = degradedReason ?? "metrics unavailable"
        }

        remoteCleanup = cleanup(remoteURL)
        readbackCleanup = cleanup(readbackURL)
        cleanupEmptyProbeDirectories(probeDirectory: probeDirectory, probeRoot: probeRoot)

        do {
            dfAfterCleanup = try await diskUsage.snapshot(for: mountDirectory, phase: .afterCleanup)
        } catch {
            degradedReason = degradedReason ?? "df after cleanup unavailable: \(error.localizedDescription)"
        }

        if settleAfterCleanupNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: settleAfterCleanupNanoseconds)
        }

        endedAt = Date()

        if checksumStatus == .fail {
            failureReason = "checksum mismatch"
            return result(outcome: .failed)
        }

        if remoteCleanup.isFailure || readbackCleanup.isFailure {
            failureReason = "cleanup failed"
            return result(outcome: .failed)
        }

        if result(outcome: .success).isVerySlow {
            degradedReason = degradedReason ?? "probe slower than expected"
            return result(outcome: .degraded)
        }

        if degradedReason != nil {
            return result(outcome: .degraded)
        }

        return result(outcome: .success)
    }

    private func writeGeneratedData(to url: URL, sizeBytes: Int64) throws -> ProbeDigest {
        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw PerformanceTestError.cannotCreateFile(url.path)
        }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        var offset: Int64 = 0
        while offset < sizeBytes {
            let nextSize = min(chunkSize, Int(sizeBytes - offset))
            let chunk = try byteGenerator.makeChunk(offset: offset, size: nextSize)
            try handle.write(contentsOf: chunk)
            hasher.update(data: chunk)
            offset += Int64(nextSize)
        }
        return ProbeDigest(hasher.finalize())
    }

    private func copyAndChecksum(from source: URL, to destination: URL) throws -> ProbeDigest {
        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw PerformanceTestError.cannotCreateFile(destination.path)
        }

        let reader = try FileHandle(forReadingFrom: source)
        let writer = try FileHandle(forWritingTo: destination)
        defer {
            try? reader.close()
            try? writer.close()
        }

        var hasher = SHA256()
        while true {
            let data = try reader.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty { break }
            try writer.write(contentsOf: data)
            hasher.update(data: data)
        }
        return ProbeDigest(hasher.finalize())
    }

    private func cleanup(_ url: URL) -> CleanupStatus {
        guard fileManager.fileExists(atPath: url.path) else {
            return .notPresent
        }

        do {
            try fileManager.removeItem(at: url)
            return .removed
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func cleanupEmptyProbeDirectories(probeDirectory: URL, probeRoot: URL) {
        removeIfEmpty(probeDirectory)
        removeIfEmpty(probeRoot)
    }

    private func removeIfEmpty(_ directory: URL) {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path),
              contents.isEmpty else {
            return
        }
        try? fileManager.removeItem(at: directory)
    }
}

private extension CleanupStatus {
    var isFailure: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
}

private extension ProbeResult {
    var isVerySlow: Bool {
        if writeSeconds >= ProbeDefaults.degradedOperationSeconds ||
            readSeconds >= ProbeDefaults.degradedOperationSeconds {
            return true
        }

        let writeThroughput = writeBytesPerSecond ?? .greatestFiniteMagnitude
        let readThroughput = readBytesPerSecond ?? .greatestFiniteMagnitude
        return writeThroughput < ProbeDefaults.degradedThroughputBytesPerSecond ||
            readThroughput < ProbeDefaults.degradedThroughputBytesPerSecond
    }

    func sanitizedForStorage() -> ProbeResult {
        ProbeResult(
            id: id,
            profileID: profileID,
            trigger: trigger,
            outcome: outcome,
            startedAt: startedAt,
            endedAt: endedAt,
            sizeBytes: sizeBytes,
            writeSeconds: writeSeconds,
            readSeconds: readSeconds,
            checksumStatus: checksumStatus,
            remoteCleanup: remoteCleanup.sanitizedForStorage(),
            readbackCleanup: readbackCleanup.sanitizedForStorage(),
            dfBeforeWrite: dfBeforeWrite?.sanitizedForStorage(),
            dfAfterWrite: dfAfterWrite?.sanitizedForStorage(),
            dfAfterCleanup: dfAfterCleanup?.sanitizedForStorage(),
            metricsSummary: ProbeResultSanitizer.sanitize(metricsSummary),
            failureReason: failureReason.map(ProbeResultSanitizer.sanitize)
        )
    }
}

private extension CleanupStatus {
    func sanitizedForStorage() -> CleanupStatus {
        switch self {
        case .removed, .notPresent:
            return self
        case .failed(let reason):
            return .failed(ProbeResultSanitizer.sanitize(reason))
        }
    }
}

private extension DiskUsageSnapshot {
    func sanitizedForStorage() -> DiskUsageSnapshot {
        DiskUsageSnapshot(
            phase: phase,
            path: ProbeResultSanitizer.sanitize(path),
            rawOutput: ProbeResultSanitizer.sanitize(rawOutput)
        )
    }
}

private enum ProbeResultSanitizer {
    private static let maxStringLength = 8_192
    private static let redaction = "[REDACTED]"
    private static let patterns = [
        #"AK[A-Z0-9]{16,}"#,
        #"[A-Za-z0-9+/=]{32,}"#
    ]

    static func sanitize(_ value: String) -> String {
        var sanitized = value
        for pattern in patterns {
            sanitized = replacing(pattern: pattern, in: sanitized)
        }
        if sanitized.count > maxStringLength {
            sanitized = String(sanitized.prefix(maxStringLength)) + "\n[truncated]"
        }
        return sanitized
    }

    private static func replacing(pattern: String, in value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: redaction)
    }
}

private func sanitizedProfileFileName(_ rawValue: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
    let sanitized = rawValue.unicodeScalars
        .map { allowed.contains($0) ? String($0) : "-" }
        .joined()
    let fileName = sanitized.isEmpty ? "profile" : sanitized
    return "\(fileName).json"
}

private struct ProbeDigest: Equatable {
    private var bytes: [UInt8]

    init(_ digest: SHA256.Digest) {
        self.bytes = Array(digest)
    }
}
