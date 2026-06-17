import Foundation
import CryptoKit
import ZeroFSManagerDomain

public enum ChecksumStatus: String, Codable, Equatable, Sendable {
    case pass
    case fail
}

public enum CleanupStatus: Equatable, Sendable {
    case removed
    case notPresent
    case failed(String)
}

public enum PerformanceTestError: Error, CustomStringConvertible, Sendable {
    case invalidSize(Int64)
    case mountNotAvailable(String)
    case cannotCreateFile(String)

    public var description: String {
        switch self {
        case .invalidSize(let size):
            "Performance test size must be positive; got \(size)"
        case .mountNotAvailable(let path):
            "Mount directory is not available: \(path)"
        case .cannotCreateFile(let path):
            "Cannot create performance test file at \(path)"
        }
    }
}

public protocol PerformanceHelper {
    func flush(profileID: ProfileID) async throws
}

public protocol MetricsProvider {
    func metrics() async throws -> String
}

public protocol DiskUsageProvider {
    func snapshot(for url: URL, phase: DiskUsagePhase) async throws -> DiskUsageSnapshot
}

public protocol ByteGenerator {
    func makeChunk(offset: Int64, size: Int) throws -> Data
}

public enum DiskUsagePhase: String, Codable, Equatable, Sendable {
    case beforeWrite
    case afterWrite
    case afterCleanup
}

public struct DiskUsageSnapshot: Equatable, Sendable {
    public var phase: DiskUsagePhase
    public var path: String
    public var rawOutput: String

    public init(phase: DiskUsagePhase, path: String, rawOutput: String) {
        self.phase = phase
        self.path = path
        self.rawOutput = rawOutput
    }
}

public struct PerformanceReport: Equatable, Sendable {
    public var profileID: ProfileID
    public var sizeBytes: Int64
    public var checksumStatus: ChecksumStatus
    public var writeSeconds: TimeInterval
    public var readSeconds: TimeInterval
    public var dfBeforeWrite: DiskUsageSnapshot
    public var dfAfterWrite: DiskUsageSnapshot
    public var dfAfterCleanup: DiskUsageSnapshot
    public var metricsBeforeCleanup: String
    public var metricsAfterCleanup: String
    public var remoteCleanup: CleanupStatus
    public var readbackCleanup: CleanupStatus
    public var capacityNote: String

    public var metricsSnapshot: String {
        metricsBeforeCleanup
    }

    public init(
        profileID: ProfileID,
        sizeBytes: Int64,
        checksumStatus: ChecksumStatus,
        writeSeconds: TimeInterval,
        readSeconds: TimeInterval,
        dfBeforeWrite: DiskUsageSnapshot,
        dfAfterWrite: DiskUsageSnapshot,
        dfAfterCleanup: DiskUsageSnapshot,
        metricsBeforeCleanup: String,
        metricsAfterCleanup: String,
        remoteCleanup: CleanupStatus,
        readbackCleanup: CleanupStatus,
        capacityNote: String
    ) {
        self.profileID = profileID
        self.sizeBytes = sizeBytes
        self.checksumStatus = checksumStatus
        self.writeSeconds = writeSeconds
        self.readSeconds = readSeconds
        self.dfBeforeWrite = dfBeforeWrite
        self.dfAfterWrite = dfAfterWrite
        self.dfAfterCleanup = dfAfterCleanup
        self.metricsBeforeCleanup = metricsBeforeCleanup
        self.metricsAfterCleanup = metricsAfterCleanup
        self.remoteCleanup = remoteCleanup
        self.readbackCleanup = readbackCleanup
        self.capacityNote = capacityNote
    }
}

public struct PerformanceTestRunner {
    private let fileManager: FileManager
    private let helper: PerformanceHelper
    private let metrics: MetricsProvider
    private let diskUsage: DiskUsageProvider
    private let byteGenerator: ByteGenerator
    private let chunkSize: Int
    private let settleAfterCleanupNanoseconds: UInt64

    public init(
        fileManager: FileManager,
        helper: PerformanceHelper,
        metrics: MetricsProvider,
        diskUsage: DiskUsageProvider = FileManagerDiskUsageProvider(),
        byteGenerator: ByteGenerator,
        chunkSize: Int = 1_048_576,
        settleAfterCleanupNanoseconds: UInt64 = 250_000_000
    ) {
        self.fileManager = fileManager
        self.helper = helper
        self.metrics = metrics
        self.diskUsage = diskUsage
        self.byteGenerator = byteGenerator
        self.chunkSize = chunkSize
        self.settleAfterCleanupNanoseconds = settleAfterCleanupNanoseconds
    }

    public func run(
        profileID: ProfileID,
        mountDirectory: URL,
        workDirectory: URL,
        sizeBytes: Int64
    ) async throws -> PerformanceReport {
        guard sizeBytes > 0 else {
            throw PerformanceTestError.invalidSize(sizeBytes)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: mountDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw PerformanceTestError.mountNotAvailable(mountDirectory.path)
        }
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        let token = UUID().uuidString
        let remoteURL = mountDirectory.appendingPathComponent(".zerofs-manager-perf-\(token).bin")
        let readbackURL = workDirectory.appendingPathComponent("zerofs-manager-readback-\(token).bin")

        do {
            let dfBeforeWrite = try await diskUsage.snapshot(for: mountDirectory, phase: .beforeWrite)

            let writeStart = Date()
            let expectedChecksum = try writeGeneratedData(to: remoteURL, sizeBytes: sizeBytes)
            let writeSeconds = Date().timeIntervalSince(writeStart)
            let dfAfterWrite = try await diskUsage.snapshot(for: mountDirectory, phase: .afterWrite)

            try await helper.flush(profileID: profileID)

            let readStart = Date()
            let actualChecksum = try copyAndChecksum(from: remoteURL, to: readbackURL)
            let readSeconds = Date().timeIntervalSince(readStart)

            let metricsBeforeCleanup = try await metrics.metrics()
            let remoteCleanup = cleanup(remoteURL)
            let readbackCleanup = cleanup(readbackURL)
            let dfAfterCleanup = try await diskUsage.snapshot(for: mountDirectory, phase: .afterCleanup)
            if settleAfterCleanupNanoseconds > 0 {
                try await Task.sleep(nanoseconds: settleAfterCleanupNanoseconds)
            }
            let metricsAfterCleanup = try await metrics.metrics()

            return PerformanceReport(
                profileID: profileID,
                sizeBytes: sizeBytes,
                checksumStatus: expectedChecksum == actualChecksum ? .pass : .fail,
                writeSeconds: writeSeconds,
                readSeconds: readSeconds,
                dfBeforeWrite: dfBeforeWrite,
                dfAfterWrite: dfAfterWrite,
                dfAfterCleanup: dfAfterCleanup,
                metricsBeforeCleanup: metricsBeforeCleanup,
                metricsAfterCleanup: metricsAfterCleanup,
                remoteCleanup: remoteCleanup,
                readbackCleanup: readbackCleanup,
                capacityNote: "Capacity is shown from the configured ZeroFS quota and may differ from object-storage provider usage accounting."
            )
        } catch {
            _ = cleanup(remoteURL)
            _ = cleanup(readbackURL)
            throw error
        }
    }

    private func writeGeneratedData(to url: URL, sizeBytes: Int64) throws -> SHA256Digest {
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
        return SHA256Digest(hasher.finalize())
    }

    private func copyAndChecksum(from source: URL, to destination: URL) throws -> SHA256Digest {
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
        return SHA256Digest(hasher.finalize())
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
}

public struct MockPerformanceHelper: PerformanceHelper {
    public var flushResult: Result<Void, Error>

    public init(flushResult: Result<Void, Error> = .success(())) {
        self.flushResult = flushResult
    }

    public func flush(profileID: ProfileID) async throws {
        try flushResult.get()
    }
}

public struct StaticMetricsProvider: MetricsProvider {
    private var metricsTexts: [String]
    private var fallback: String

    public init(metrics: String) {
        self.metricsTexts = [metrics]
        self.fallback = metrics
    }

    public init(metricsSequence: [String]) {
        self.metricsTexts = metricsSequence
        self.fallback = metricsSequence.last ?? ""
    }

    public func metrics() async throws -> String {
        metricsTexts.first ?? fallback
    }
}

public struct PrometheusMetricsProvider: MetricsProvider {
    public var url: URL

    public init(url: URL) {
        self.url = url
    }

    public func metrics() async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

public struct StaticDiskUsageProvider: DiskUsageProvider {
    public init() {}

    public func snapshot(for url: URL, phase: DiskUsagePhase) async throws -> DiskUsageSnapshot {
        DiskUsageSnapshot(
            phase: phase,
            path: url.path,
            rawOutput: "Filesystem 1024-blocks Used Available Capacity Mounted on\nmock 1024 0 1024 0% \(url.path)"
        )
    }
}

public struct FileManagerDiskUsageProvider: DiskUsageProvider {
    public init() {}

    public func snapshot(for url: URL, phase: DiskUsagePhase) async throws -> DiskUsageSnapshot {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/df")
        process.arguments = ["-k", url.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        return DiskUsageSnapshot(phase: phase, path: url.path, rawOutput: output)
    }
}

public struct RepeatingByteGenerator: ByteGenerator {
    public var byte: UInt8

    public init(byte: UInt8) {
        self.byte = byte
    }

    public func makeChunk(offset: Int64, size: Int) throws -> Data {
        Data(repeating: byte, count: size)
    }
}

private struct SHA256Digest: Equatable {
    private var bytes: [UInt8]

    init(_ digest: SHA256.Digest) {
        self.bytes = Array(digest)
    }
}
