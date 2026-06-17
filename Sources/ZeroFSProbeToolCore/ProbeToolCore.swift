import Foundation
import ZeroFSManagerDomain
import ZeroFSPerformance

public enum ProbeToolExit: Error, Equatable {
    case code(Int32)

    public var statusCode: Int32 {
        switch self {
        case .code(let value):
            return value
        }
    }
}

public struct ProbeToolArguments: Equatable {
    public var profileID: ProfileID
    public var mountPoint: URL
    public var sizeBytes: Int64
    public var metricsPort: Int?
    public var resultDirectory: URL
    public var workDirectory: URL
    public var zerofsBinary: URL
    public var configFile: URL
    public var lockDirectory: URL?
    public var trigger: ProbeTrigger
    public var skipReason: String?

    public static let usage = """
    Usage: ZeroFSProbeTool --profile-id ID --mount-point PATH --size-bytes BYTES --result-dir PATH --work-dir PATH --zerofs-bin PATH --config PATH --trigger manual|in-app-schedule|background-launchdaemon [--metrics-port PORT] [--lock-dir PATH] [--skip-reason REASON]
    """

    public static func parse(_ commandLine: [String]) throws -> ProbeToolArguments {
        var values: [String: String] = [:]
        var iterator = commandLine.dropFirst().makeIterator()

        while let argument = iterator.next() {
            if argument == "--help" || argument == "-h" {
                throw ProbeToolError.helpRequested
            }

            guard argument.hasPrefix("--") else {
                throw ProbeToolError.invalidArgument("unexpected positional argument: \(argument)")
            }

            guard let value = iterator.next(), !value.hasPrefix("--") else {
                throw ProbeToolError.invalidArgument("missing value for \(argument)")
            }
            values[argument] = value
        }

        let profileID = try ProfileID(required("--profile-id", in: values))
        let sizeBytes = try parsePositiveInt64(required("--size-bytes", in: values), name: "--size-bytes")
        let metricsPort = try values["--metrics-port"].map { try parsePort($0) }
        let trigger = try parseTrigger(required("--trigger", in: values))

        let mountPoint = try required("--mount-point", in: values)
        let resultDirectory = try required("--result-dir", in: values)
        let workDirectory = try required("--work-dir", in: values)
        let zerofsBinary = try required("--zerofs-bin", in: values)
        let configFile = try required("--config", in: values)

        return ProbeToolArguments(
            profileID: profileID,
            mountPoint: URL(fileURLWithPath: mountPoint),
            sizeBytes: sizeBytes,
            metricsPort: metricsPort,
            resultDirectory: URL(fileURLWithPath: resultDirectory, isDirectory: true),
            workDirectory: URL(fileURLWithPath: workDirectory, isDirectory: true),
            zerofsBinary: URL(fileURLWithPath: zerofsBinary, isDirectory: false),
            configFile: URL(fileURLWithPath: configFile, isDirectory: false),
            lockDirectory: values["--lock-dir"].map { URL(fileURLWithPath: $0, isDirectory: true) },
            trigger: trigger,
            skipReason: values["--skip-reason"]
        )
    }

    private static func required(_ name: String, in values: [String: String]) throws -> String {
        guard let value = values[name], !value.isEmpty else {
            throw ProbeToolError.invalidArgument("missing required \(name)")
        }
        return value
    }

    private static func parsePositiveInt64(_ value: String, name: String) throws -> Int64 {
        guard let parsed = Int64(value), parsed > 0 else {
            throw ProbeToolError.invalidArgument("\(name) must be a positive integer")
        }
        return parsed
    }

    private static func parsePort(_ value: String) throws -> Int {
        guard let port = Int(value), (1...65_535).contains(port) else {
            throw ProbeToolError.invalidArgument("--metrics-port must be between 1 and 65535")
        }
        return port
    }

    private static func parseTrigger(_ value: String) throws -> ProbeTrigger {
        switch value {
        case "manual":
            return .manual
        case "inAppSchedule", "in-app-schedule":
            return .inAppSchedule
        case "backgroundLaunchDaemon", "background-launchdaemon", "background-launch-daemon":
            return .backgroundLaunchDaemon
        default:
            throw ProbeToolError.invalidArgument("invalid --trigger \(value)")
        }
    }
}

public enum ProbeToolSupport {
    public static func makeSkippedResult(arguments: ProbeToolArguments, reason: String) -> ProbeResult {
        ProbeResult(
            profileID: arguments.profileID,
            trigger: arguments.trigger,
            outcome: .skipped,
            startedAt: Date(),
            endedAt: Date(),
            sizeBytes: arguments.sizeBytes,
            writeSeconds: 0,
            readSeconds: 0,
            checksumStatus: .pass,
            remoteCleanup: .notPresent,
            readbackCleanup: .notPresent,
            dfBeforeWrite: nil,
            dfAfterWrite: nil,
            dfAfterCleanup: nil,
            metricsSummary: "probe skipped",
            failureReason: reason
        )
    }

    public static func redactionSecrets(from environment: [String: String]) -> [String] {
        [
            environment["AWS_ACCESS_KEY_ID"],
            environment["AWS_SECRET_ACCESS_KEY"],
            environment["ZEROFS_PASSWORD"],
            environment["S3_ACCESS_KEY"],
            environment["S3_SECRET_KEY"]
        ].compactMap { $0 }.filter { !$0.isEmpty }
    }

    public static func resultJSON(_ result: ProbeResult, redactingSecrets: [String] = []) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(result.sanitizedForStorage(redactingSecrets: redactingSecrets))
    }

    public static func writeResultJSON(_ result: ProbeResult, redactingSecrets: [String] = []) throws {
        let data = try resultJSON(result, redactingSecrets: redactingSecrets)
        try FileHandle.standardOutput.write(contentsOf: data)
        try FileHandle.standardOutput.write(contentsOf: Data("\n".utf8))
    }

    public static func exitCode(for result: ProbeResult) -> Int32 {
        switch result.outcome {
        case .success, .degraded:
            return 0
        case .failed:
            return 1
        case .skipped:
            return 75
        }
    }
}

public struct ShellPerformanceHelper: PerformanceHelper {
    public var zerofsBinaryURL: URL
    public var configURL: URL

    public init(zerofsBinaryURL: URL, configURL: URL) {
        self.zerofsBinaryURL = zerofsBinaryURL
        self.configURL = configURL
    }

    public func flush(profileID: ProfileID) async throws {
        let process = Process()
        process.executableURL = zerofsBinaryURL
        process.arguments = ["flush", "--config", configURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw ProbeToolError.commandFailed("zerofs flush failed: \(output)")
        }
    }
}

public enum ProbeToolError: Error, CustomStringConvertible, Equatable {
    case helpRequested
    case invalidArgument(String)
    case commandFailed(String)

    public var description: String {
        switch self {
        case .helpRequested:
            return ProbeToolArguments.usage
        case .invalidArgument(let message), .commandFailed(let message):
            return message
        }
    }
}
