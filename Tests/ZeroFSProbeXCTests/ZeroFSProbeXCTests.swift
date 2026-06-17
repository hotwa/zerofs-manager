#if canImport(XCTest)
import Foundation
import XCTest
import ZeroFSManagerDomain
import ZeroFSPerformance
import ZeroFSProbeToolCore

final class ZeroFSProbeXCTests: XCTestCase {
    func testConfirmedManualProbePolicySupports512MiB() {
        XCTAssertEqual(
            ProbeSizePolicy.resolvedManualSize(requestedBytes: 512 * 1_048_576, confirmedLarge: true),
            ProbeDefaults.confirmedManualMaxSizeBytes
        )
        XCTAssertEqual(
            ProbeSizePolicy.resolvedManualSize(requestedBytes: 512 * 1_048_576, confirmedLarge: false),
            ProbeDefaults.manualMaxSizeBytesWithoutConfirmation
        )
    }

    func testHistoryAwareClassificationMarksRecentDropAsDegraded() throws {
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

        XCTAssertEqual(
            ReliabilityClassifier.classification(
                settings: ProbeSettings(enabled: true),
                latestResult: latest,
                history: [latest] + baseline
            ),
            .degraded
        )
    }

    func testProbeToolSkippedResultExitAndSanitizedJSON() throws {
        let arguments = try ProbeToolArguments.parse([
            "ZeroFSProbeTool",
            "--profile-id", "example-profile",
            "--mount-point", "/Volumes/ZeroFS-example",
            "--size-bytes", "1048576",
            "--result-dir", "/tmp/results",
            "--work-dir", "/tmp/work",
            "--zerofs-bin", "/usr/local/bin/zerofs",
            "--config", "/tmp/zerofs.toml",
            "--trigger", "background-launchdaemon",
            "--skip-reason", "mount not ready"
        ])
        let secret = "probe-secret"
        let result = ProbeToolSupport.makeSkippedResult(
            arguments: arguments,
            reason: "previous probe is already running with \(secret)"
        )
        let json = try ProbeToolSupport.resultJSON(result, redactingSecrets: [secret])
        let text = String(decoding: json, as: UTF8.self)

        XCTAssertEqual(ProbeToolSupport.exitCode(for: result), 75)
        XCTAssertFalse(text.contains(secret))
        XCTAssertTrue(text.contains("[REDACTED]"))
    }

    private func makeResult(
        profileID: ProfileID,
        startedAt: Date,
        sizeBytes: Int64,
        writeSeconds: TimeInterval,
        readSeconds: TimeInterval
    ) -> ProbeResult {
        ProbeResult(
            profileID: profileID,
            trigger: .manual,
            outcome: .success,
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
            failureReason: nil
        )
    }
}
#endif
