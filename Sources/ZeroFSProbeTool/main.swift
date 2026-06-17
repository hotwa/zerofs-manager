import Foundation
import ZeroFSManagerDomain
import ZeroFSPerformance

#if canImport(Darwin)
import Darwin
#endif

@main
struct ZeroFSProbeTool {
    static func main() async {
        do {
            let arguments = try ProbeToolArguments.parse(CommandLine.arguments)
            let resultStore = FileProbeResultStore(directoryURL: arguments.resultDirectory)

            let lockHandle: ProbeRunLockHandle?
            if let lockDirectory = arguments.lockDirectory {
                guard let acquiredLock = try ProbeRunLock(lockDirectory: lockDirectory).acquire() else {
                    let skipped = ProbeResult(
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
                        failureReason: "previous probe is already running"
                    )
                    try resultStore.append(skipped)
                    try writeResultJSON(skipped)
                    throw ProbeToolExit.code(75)
                }
                lockHandle = acquiredLock
            } else {
                lockHandle = nil
            }
            defer { lockHandle?.release() }

            let helper = ShellPerformanceHelper(
                zerofsBinaryURL: arguments.zerofsBinary,
                configURL: arguments.configFile
            )
            let metricsProvider: any MetricsProvider
            if let metricsPort = arguments.metricsPort {
                metricsProvider = PrometheusMetricsProvider(
                    url: URL(string: "http://127.0.0.1:\(metricsPort)/metrics")!
                )
            } else {
                metricsProvider = StaticMetricsProvider(metrics: "metrics unavailable: metrics port not provided")
            }
            let runner = ReliabilityProbeRunner(
                fileManager: .default,
                helper: helper,
                metrics: metricsProvider,
                diskUsage: FileManagerDiskUsageProvider(),
                byteGenerator: RandomByteGenerator(),
                mountTable: SystemMountTableProvider()
            )
            let result = await runner.run(
                profileID: arguments.profileID,
                mountDirectory: arguments.mountPoint,
                workDirectory: arguments.workDirectory,
                sizeBytes: arguments.sizeBytes,
                trigger: arguments.trigger
            )
            try resultStore.append(result)
            try writeResultJSON(result)

            switch result.outcome {
            case .success, .degraded:
                return
            case .failed:
                throw ProbeToolExit.code(1)
            case .skipped:
                throw ProbeToolExit.code(75)
            }
        } catch ProbeToolError.helpRequested {
            print(ProbeToolArguments.usage)
        } catch ProbeToolExit.code(let code) {
            terminate(code)
        } catch {
            fputs("ZeroFSProbeTool: \(error)\n", stderr)
            terminate(2)
        }
    }

    private static func writeResultJSON(_ result: ProbeResult) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(result)
        try FileHandle.standardOutput.write(contentsOf: data)
        try FileHandle.standardOutput.write(contentsOf: Data("\n".utf8))
    }

}

private enum ProbeToolExit: Error {
    case code(Int32)
}

private struct ProbeToolArguments {
    var profileID: ProfileID
    var mountPoint: URL
    var sizeBytes: Int64
    var metricsPort: Int?
    var resultDirectory: URL
    var workDirectory: URL
    var zerofsBinary: URL
    var configFile: URL
    var lockDirectory: URL?
    var trigger: ProbeTrigger

    static let usage = """
    Usage: ZeroFSProbeTool --profile-id ID --mount-point PATH --size-bytes BYTES --result-dir PATH --work-dir PATH --zerofs-bin PATH --config PATH --trigger manual|in-app-schedule|background-launchdaemon [--metrics-port PORT] [--lock-dir PATH]
    """

    static func parse(_ commandLine: [String]) throws -> ProbeToolArguments {
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
            trigger: trigger
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

private struct ShellPerformanceHelper: PerformanceHelper {
    var zerofsBinaryURL: URL
    var configURL: URL

    func flush(profileID: ProfileID) async throws {
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

private enum ProbeToolError: Error, CustomStringConvertible {
    case helpRequested
    case invalidArgument(String)
    case commandFailed(String)

    var description: String {
        switch self {
        case .helpRequested:
            return ProbeToolArguments.usage
        case .invalidArgument(let message), .commandFailed(let message):
            return message
        }
    }
}

private func terminate(_ code: Int32) -> Never {
    #if canImport(Darwin)
    Darwin.exit(code)
    #else
    Foundation.exit(code)
    #endif
}
