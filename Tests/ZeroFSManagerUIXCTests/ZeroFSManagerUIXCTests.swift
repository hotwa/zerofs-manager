#if canImport(XCTest)
import Foundation
import XCTest
import ZeroFSManagerDomain
import ZeroFSPerformance
@testable import ZeroFSManagerUI

final class ZeroFSManagerUIXCTests: XCTestCase {
    func testCleanupSummaryIsLocalizedPerLanguage() throws {
        let result = makeResult(
            remoteCleanup: .removed,
            readbackCleanup: .notPresent
        )

        XCTAssertEqual(
            AppLanguage.english.probeCleanupSummary(for: result.diagnostics.cleanup),
            "Remote removed, readback not present"
        )
        XCTAssertEqual(
            AppLanguage.simplifiedChinese.probeCleanupSummary(for: result.diagnostics.cleanup),
            "远端已删除，读回文件不存在"
        )
        XCTAssertEqual(
            AppLanguage.traditionalChinese.probeCleanupSummary(for: result.diagnostics.cleanup),
            "遠端已刪除，讀回檔不存在"
        )
        XCTAssertEqual(
            AppLanguage.japanese.probeCleanupSummary(for: result.diagnostics.cleanup),
            "リモート削除済み、読み戻しなし"
        )
        XCTAssertEqual(
            AppLanguage.korean.probeCleanupSummary(for: result.diagnostics.cleanup),
            "원격 삭제됨, 읽기 복사본 없음"
        )
    }

    func testHistoryClassificationOnlyUsesSamplesBeforeResult() throws {
        let profileID = try ProfileID("example-profile")
        let olderResult = makeResult(
            profileID: profileID,
            startedAt: Date(timeIntervalSince1970: 10),
            sizeBytes: 10 * 1_048_576,
            writeSeconds: 0.25,
            readSeconds: 0.20
        )
        let futureFastBaseline = (0..<10).map { index in
            makeResult(
                profileID: profileID,
                startedAt: Date(timeIntervalSince1970: Double(20 + index)),
                sizeBytes: 10 * 1_048_576,
                writeSeconds: 0.10,
                readSeconds: 0.10
            )
        }

        let fullHistory = ([olderResult] + futureFastBaseline).sorted { $0.startedAt > $1.startedAt }

        XCTAssertEqual(
            ProbeHistoryDisplay.classification(for: olderResult, in: fullHistory),
            .healthy
        )
    }

    private func makeResult(
        profileID: ProfileID = (try! ProfileID("example-profile")),
        startedAt: Date = Date(timeIntervalSince1970: 1_000),
        sizeBytes: Int64 = 4 * 1_048_576,
        writeSeconds: TimeInterval = 0.10,
        readSeconds: TimeInterval = 0.10,
        remoteCleanup: CleanupStatus = .removed,
        readbackCleanup: CleanupStatus = .removed
    ) -> ProbeResult {
        ProbeResult(
            profileID: profileID,
            trigger: .manual,
            outcome: .success,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(writeSeconds + readSeconds + 0.10),
            sizeBytes: sizeBytes,
            writeSeconds: writeSeconds,
            readSeconds: readSeconds,
            checksumStatus: .pass,
            remoteCleanup: remoteCleanup,
            readbackCleanup: readbackCleanup,
            dfBeforeWrite: nil,
            dfAfterWrite: nil,
            dfAfterCleanup: nil,
            metricsSummary: "",
            failureReason: nil
        )
    }
}
#endif
