import Foundation
import ZeroFSManagerDomain
import ZeroFSPerformance
import ZeroFSProbeToolCore

#if canImport(Darwin)
import Darwin
#endif

@main
struct ZeroFSProbeTool {
    static func main() async {
        do {
            let arguments = try ProbeToolArguments.parse(CommandLine.arguments)
            let resultStore = FileProbeResultStore(directoryURL: arguments.resultDirectory)
            let redactionSecrets = ProbeToolSupport.redactionSecrets(from: ProcessInfo.processInfo.environment)

            let lockHandle: ProbeRunLockHandle?
            if let lockDirectory = arguments.lockDirectory {
                guard let acquiredLock = try ProbeRunLock(lockDirectory: lockDirectory).acquire() else {
                    let skipped = ProbeToolSupport.makeSkippedResult(arguments: arguments, reason: "previous probe is already running")
                    try resultStore.append(skipped, redactingSecrets: redactionSecrets)
                    try ProbeToolSupport.writeResultJSON(skipped, redactingSecrets: redactionSecrets)
                    throw ProbeToolExit.code(75)
                }
                lockHandle = acquiredLock
            } else {
                lockHandle = nil
            }
            defer { lockHandle?.release() }

            if let skipReason = arguments.skipReason {
                let skipped = ProbeToolSupport.makeSkippedResult(arguments: arguments, reason: skipReason)
                try resultStore.append(skipped, redactingSecrets: redactionSecrets)
                try ProbeToolSupport.writeResultJSON(skipped, redactingSecrets: redactionSecrets)
                throw ProbeToolExit.code(75)
            }

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
            try resultStore.append(result, redactingSecrets: redactionSecrets)
            let sanitizedResult = result.sanitizedForStorage(redactingSecrets: redactionSecrets)
            try ProbeToolSupport.writeResultJSON(sanitizedResult)

            let exitCode = ProbeToolSupport.exitCode(for: sanitizedResult)
            if exitCode == 0 {
                return
            }
            throw ProbeToolExit.code(exitCode)
        } catch ProbeToolError.helpRequested {
            print(ProbeToolArguments.usage)
        } catch ProbeToolExit.code(let code) {
            terminate(code)
        } catch {
            fputs("ZeroFSProbeTool: \(error)\n", stderr)
            terminate(2)
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
