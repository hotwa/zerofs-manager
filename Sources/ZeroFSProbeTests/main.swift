import Foundation
import ZeroFSManagerDomain
import ZeroFSPerformance
import ZeroFSProbeToolCore

@main
struct ZeroFSProbeTests {
    static func main() throws {
        var checks = ProbeTestSuite()
        try checkProbeSettingsDecodeLegacyJSONDefaultsNewFields(&checks)
        checkManualProbeSizePolicyRequiresConfirmationAboveSafeLimit(&checks)
        try checkHistoryAwareClassificationDegradesWhenLatestFallsBelowHalfMedian(&checks)
        try checkHistoryAwareClassificationRequiresEnoughSuccessfulHistory(&checks)
        try checkProbeSettingsPersistManualAndScheduledTimestamps(&checks)
        try checkProbeResultDiagnosticsExposeThroughputDurationCleanupAndFailure(&checks)
        try checkProbeResultStoreRetentionAndSecretSanitization(&checks)
        try checkProbeRunLockBlocksConcurrentAcquisition(&checks)
        try checkParseSupportsSkipReasonAndBackgroundTrigger(&checks)
        try checkSkippedLockResultUsesTemporaryExitCodeAndSanitizedJSON(&checks)
        try checkSkipReasonResultUsesTemporaryExitCode(&checks)
        try checkFailedProbeUsesFailureExitCodeAndSanitizedJSON(&checks)
        checkRedactionSecretsReadExpectedEnvironmentKeys(&checks)
        checks.finish()
    }

    private static func checkProbeSettingsDecodeLegacyJSONDefaultsNewFields(_ checks: inout ProbeTestSuite) throws {
        let json = """
        {
          "enabled": true,
          "intervalSeconds": 900,
          "sizeBytes": 1048576,
          "backgroundLaunchDaemonEnabled": false
        }
        """

        let settings = try JSONDecoder().decode(ProbeSettings.self, from: Data(json.utf8))

        checks.expect(settings.enabled, "legacy probe settings preserve enabled flag")
        checks.expect(settings.intervalSeconds == 900, "legacy probe settings preserve interval")
        checks.expect(settings.sizeBytes == 1_048_576, "legacy probe settings preserve scheduled size")
        checks.expect(settings.manualSizeBytes == 1_048_576, "legacy probe settings default manual size from old size field")
        checks.expect(settings.lastScheduledProbeAt == nil, "legacy probe settings default missing scheduled timestamp")
        checks.expect(settings.lastManualProbeAt == nil, "legacy probe settings default missing manual timestamp")
    }

    private static func checkManualProbeSizePolicyRequiresConfirmationAboveSafeLimit(_ checks: inout ProbeTestSuite) {
        checks.expect(
            ProbeSizePolicy.resolvedScheduledSize(requestedBytes: 512 * 1_048_576) == ProbeDefaults.scheduledMaxSizeBytes,
            "scheduled probes remain capped at 16 MiB"
        )
        checks.expect(
            ProbeSizePolicy.resolvedManualSize(requestedBytes: 512 * 1_048_576, confirmedLarge: false) == ProbeDefaults.manualMaxSizeBytesWithoutConfirmation,
            "unconfirmed manual probes remain capped at 64 MiB"
        )
        checks.expect(
            ProbeSizePolicy.resolvedManualSize(requestedBytes: 512 * 1_048_576, confirmedLarge: true) == ProbeDefaults.confirmedManualMaxSizeBytes,
            "confirmed manual probes support 512 MiB"
        )
        checks.expect(
            ProbeSizePolicy.resolvedManualSize(requestedBytes: 1_024 * 1_048_576, confirmedLarge: true) == ProbeDefaults.confirmedManualMaxSizeBytes,
            "confirmed manual probes still cap above 512 MiB"
        )
    }

    private static func checkHistoryAwareClassificationDegradesWhenLatestFallsBelowHalfMedian(_ checks: inout ProbeTestSuite) throws {
        let profileID = try ProfileID("example-profile")
        let baseline = (0..<10).map { index in
            makeResult(
                profileID: profileID,
                startedAt: Date(timeIntervalSince1970: Double(index)),
                sizeBytes: 10 * 1_048_576,
                writeSeconds: 0.10,
                readSeconds: 0.10
            )
        }
        let latest = makeResult(
            profileID: profileID,
            startedAt: Date(timeIntervalSince1970: 20),
            sizeBytes: 10 * 1_048_576,
            writeSeconds: 0.25,
            readSeconds: 0.20
        )

        let classification = ReliabilityClassifier.classification(
            settings: ProbeSettings(enabled: true),
            latestResult: latest,
            history: [latest] + baseline
        )

        checks.expect(classification == .degraded, "history-aware classifier marks latest as degraded below half median")
    }

    private static func checkHistoryAwareClassificationRequiresEnoughSuccessfulHistory(_ checks: inout ProbeTestSuite) throws {
        let profileID = try ProfileID("example-profile")
        let baseline = (0..<2).map { index in
            makeResult(
                profileID: profileID,
                startedAt: Date(timeIntervalSince1970: Double(index)),
                sizeBytes: 10 * 1_048_576,
                writeSeconds: 0.10,
                readSeconds: 0.10
            )
        }
        let latest = makeResult(
            profileID: profileID,
            startedAt: Date(timeIntervalSince1970: 20),
            sizeBytes: 10 * 1_048_576,
            writeSeconds: 0.25,
            readSeconds: 0.20
        )

        let classification = ReliabilityClassifier.classification(
            settings: ProbeSettings(enabled: true),
            latestResult: latest,
            history: [latest] + baseline
        )

        checks.expect(classification == .healthy, "history-aware classifier ignores insufficient history")
    }

    private static func checkProbeSettingsPersistManualAndScheduledTimestamps(_ checks: inout ProbeTestSuite) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileProbeSettingsStore(fileURL: root.appendingPathComponent("probe-settings.json"))
        let profileID = try ProfileID("example-profile")
        let scheduledAt = Date(timeIntervalSince1970: 1_000)
        let manualAt = Date(timeIntervalSince1970: 2_000)
        let settings = ProbeSettings(
            enabled: true,
            intervalSeconds: 900,
            sizeBytes: 1_048_576,
            manualSizeBytes: 512 * 1_048_576,
            backgroundLaunchDaemonEnabled: false,
            lastScheduledProbeAt: scheduledAt,
            lastManualProbeAt: manualAt
        )

        try store.save([profileID: settings])
        guard let loaded = try store.load()[profileID] else {
            checks.expect(false, "probe settings load saved profile")
            return
        }

        checks.expect(loaded.lastScheduledProbeAt == scheduledAt, "probe settings persist scheduled timestamp")
        checks.expect(loaded.lastManualProbeAt == manualAt, "probe settings persist manual timestamp")
        checks.expect(loaded.manualSizeBytes == 512 * 1_048_576, "probe settings persist manual probe size")
    }

    private static func checkProbeResultDiagnosticsExposeThroughputDurationCleanupAndFailure(_ checks: inout ProbeTestSuite) throws {
        let profileID = try ProfileID("example-profile")
        let result = makeResult(
            profileID: profileID,
            sizeBytes: 8 * 1_048_576,
            writeSeconds: 2,
            readSeconds: 4,
            outcome: .failed,
            failureReason: "checksum mismatch"
        )

        checks.expect(abs((result.diagnostics.writeMiBPerSecond ?? 0) - 4) < 0.001, "diagnostics expose write throughput")
        checks.expect(abs((result.diagnostics.readMiBPerSecond ?? 0) - 2) < 0.001, "diagnostics expose read throughput")
        checks.expect(result.diagnostics.durationSeconds == result.durationSeconds, "diagnostics expose duration")
        checks.expect(result.diagnostics.cleanup.remote == .removed, "diagnostics expose structured remote cleanup state")
        checks.expect(result.diagnostics.cleanup.readback == .removed, "diagnostics expose structured readback cleanup state")
        checks.expect(result.diagnostics.failureReason == "checksum mismatch", "diagnostics expose concise failure")
    }

    private static func checkProbeResultStoreRetentionAndSecretSanitization(_ checks: inout ProbeTestSuite) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileProbeResultStore(
            directoryURL: root,
            retention: ProbeResultRetention(maxRecordsPerProfile: 2, maxAgeSeconds: 60)
        )
        let profileID = try ProfileID("example-profile")
        let secret = "secret-fixture-value"
        let now = Date()
        var old = makeResult(profileID: profileID, startedAt: now.addingTimeInterval(-120))
        old.failureReason = secret
        var first = makeResult(profileID: profileID, startedAt: now.addingTimeInterval(-2))
        first.failureReason = secret
        let second = makeResult(profileID: profileID, startedAt: now.addingTimeInterval(-1))

        try store.append(old, redactingSecrets: [secret])
        try store.append(first, redactingSecrets: [secret])
        try store.append(second, redactingSecrets: [secret])

        let loaded = try store.load(profileID: profileID)
        let serialized = try String(contentsOf: store.fileURL(for: profileID), encoding: .utf8)
        checks.expect(loaded.count == 2, "probe result store prunes by age and count")
        checks.expect(!loaded.contains { $0.id == old.id }, "probe result store drops expired records")
        checks.expect(!serialized.contains(secret), "probe result store redacts explicit secrets")
    }

    private static func checkProbeRunLockBlocksConcurrentAcquisition(_ checks: inout ProbeTestSuite) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lock = ProbeRunLock(lockDirectory: root.appendingPathComponent("probe.lock"), staleAfterSeconds: 60)

        guard let first = try lock.acquire(processIdentifier: ProcessInfo.processInfo.processIdentifier) else {
            checks.expect(false, "probe run lock can be acquired")
            return
        }
        try checks.expect(try lock.acquire(processIdentifier: ProcessInfo.processInfo.processIdentifier) == nil, "probe run lock blocks concurrent acquisition")
        first.release()
        let second = try lock.acquire(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        checks.expect(second != nil, "probe run lock releases cleanly")
        second?.release()
    }

    private static func checkParseSupportsSkipReasonAndBackgroundTrigger(_ checks: inout ProbeTestSuite) throws {
        let args = try ProbeToolArguments.parse([
            "ZeroFSProbeTool",
            "--profile-id", "example-profile",
            "--mount-point", "/Volumes/ZeroFS-example",
            "--size-bytes", "1048576",
            "--result-dir", "/tmp/results",
            "--work-dir", "/tmp/work",
            "--zerofs-bin", "/usr/local/bin/zerofs",
            "--config", "/Library/Application Support/ZeroFSManager/Profiles/example-profile/zerofs.toml",
            "--trigger", "background-launchdaemon",
            "--skip-reason", "mount not ready"
        ])

        checks.expect(args.profileID.rawValue == "example-profile", "probe tool parses profile id")
        checks.expect(args.trigger == .backgroundLaunchDaemon, "probe tool parses background trigger")
        checks.expect(args.skipReason == "mount not ready", "probe tool parses skip reason")
    }

    private static func checkSkippedLockResultUsesTemporaryExitCodeAndSanitizedJSON(_ checks: inout ProbeTestSuite) throws {
        let secret = "sensitive-token"
        let args = try makeArguments(skipReason: nil)
        let result = ProbeToolSupport.makeSkippedResult(
            arguments: args,
            reason: "previous probe is already running with \(secret)"
        )
        let json = try ProbeToolSupport.resultJSON(result, redactingSecrets: [secret])
        let decoded = try JSONDecoder.probeTool.decode(ProbeResult.self, from: json)

        checks.expect(result.outcome == .skipped, "probe tool lock skip result is skipped")
        checks.expect(ProbeToolSupport.exitCode(for: result) == 75, "probe tool lock skip exits temporary failure")
        checks.expect(decoded.failureReason == "previous probe is already running with [REDACTED]", "probe tool JSON redacts lock skip reason")
        checks.expect(!String(decoding: json, as: UTF8.self).contains(secret), "probe tool JSON excludes explicit secret")
    }

    private static func checkSkipReasonResultUsesTemporaryExitCode(_ checks: inout ProbeTestSuite) throws {
        let args = try makeArguments(skipReason: "mount not ready")
        guard let skipReason = args.skipReason else {
            checks.expect(false, "probe tool retains skip reason")
            return
        }
        let result = ProbeToolSupport.makeSkippedResult(arguments: args, reason: skipReason)

        checks.expect(result.outcome == .skipped, "probe tool skip-reason result is skipped")
        checks.expect(result.failureReason == "mount not ready", "probe tool skip-reason result keeps reason")
        checks.expect(ProbeToolSupport.exitCode(for: result) == 75, "probe tool skip-reason exits temporary failure")
    }

    private static func checkFailedProbeUsesFailureExitCodeAndSanitizedJSON(_ checks: inout ProbeTestSuite) throws {
        let profileID = try ProfileID("example-profile")
        let secret = "flush-secret-output"
        let result = ProbeResult(
            profileID: profileID,
            trigger: .backgroundLaunchDaemon,
            outcome: .failed,
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 1),
            sizeBytes: 1_048_576,
            writeSeconds: 0,
            readSeconds: 0,
            checksumStatus: .fail,
            remoteCleanup: .notPresent,
            readbackCleanup: .notPresent,
            dfBeforeWrite: nil,
            dfAfterWrite: nil,
            dfAfterCleanup: nil,
            metricsSummary: "metrics unavailable",
            failureReason: "zerofs flush failed: \(secret)"
        )

        let json = try ProbeToolSupport.resultJSON(result, redactingSecrets: [secret])
        let decoded = try JSONDecoder.probeTool.decode(ProbeResult.self, from: json)

        checks.expect(ProbeToolSupport.exitCode(for: result) == 1, "failed probe exits failure")
        checks.expect(decoded.failureReason == "zerofs flush failed: [REDACTED]", "failed probe JSON redacts flush output")
        checks.expect(!String(decoding: json, as: UTF8.self).contains(secret), "failed probe JSON excludes explicit secret")
    }

    private static func checkRedactionSecretsReadExpectedEnvironmentKeys(_ checks: inout ProbeTestSuite) {
        let secrets = ProbeToolSupport.redactionSecrets(from: [
            "AWS_ACCESS_KEY_ID": "access",
            "AWS_SECRET_ACCESS_KEY": "secret",
            "ZEROFS_PASSWORD": "password",
            "IGNORED": "value"
        ])

        checks.expect(Set(secrets) == Set(["access", "secret", "password"]), "probe tool reads expected redaction environment keys")
    }

    private static func makeArguments(skipReason: String?) throws -> ProbeToolArguments {
        var command = [
            "ZeroFSProbeTool",
            "--profile-id", "example-profile",
            "--mount-point", "/Volumes/ZeroFS-example",
            "--size-bytes", "1048576",
            "--result-dir", "/tmp/results",
            "--work-dir", "/tmp/work",
            "--zerofs-bin", "/usr/local/bin/zerofs",
            "--config", "/tmp/zerofs.toml",
            "--trigger", "backgroundLaunchDaemon"
        ]
        if let skipReason {
            command.append(contentsOf: ["--skip-reason", skipReason])
        }
        return try ProbeToolArguments.parse(command)
    }

    private static func makeResult(
        profileID: ProfileID,
        startedAt: Date = Date(timeIntervalSince1970: 0),
        sizeBytes: Int64 = 1_048_576,
        writeSeconds: TimeInterval = 0.1,
        readSeconds: TimeInterval = 0.1,
        outcome: ProbeOutcome = .success,
        failureReason: String? = nil
    ) -> ProbeResult {
        ProbeResult(
            profileID: profileID,
            trigger: .manual,
            outcome: outcome,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(writeSeconds + readSeconds + 0.1),
            sizeBytes: sizeBytes,
            writeSeconds: writeSeconds,
            readSeconds: readSeconds,
            checksumStatus: .pass,
            remoteCleanup: .removed,
            readbackCleanup: .removed,
            dfBeforeWrite: nil,
            dfAfterWrite: nil,
            dfAfterCleanup: nil,
            metricsSummary: "",
            failureReason: failureReason
        )
    }
}

private struct ProbeTestSuite {
    private var failures: [String] = []

    mutating func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
        if try !condition() {
            failures.append(message)
            fputs("FAIL: \(message)\n", stderr)
        } else {
            print("PASS: \(message)")
        }
    }

    func finish() -> Never {
        if failures.isEmpty {
            print("ZeroFSProbeTests: all checks passed")
            Foundation.exit(0)
        }
        fputs("ZeroFSProbeTests: \(failures.count) failure(s)\n", stderr)
        Foundation.exit(1)
    }
}

private extension JSONDecoder {
    static var probeTool: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
