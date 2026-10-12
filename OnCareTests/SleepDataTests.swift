import XCTest
@testable import OnCare

final class SleepDataTests: XCTestCase {
    func richEntry() -> Entry {
        let end = Date(timeIntervalSince1970: floor((Date().timeIntervalSince1970 - 600) * 1000) / 1000), start = end.addingTimeInterval(-8 * 3600)
        func stage(_ from: Double, _ to: Double, _ type: SleepStageType) -> SleepStage { SleepStage(start: start.addingTimeInterval(from * 60), end: start.addingTimeInterval(to * 60), type: type) }
        let details = SleepDetails(stages: [stage(0, 30, .awake), stage(30, 150, .light), stage(150, 210, .deep), stage(210, 300, .rem), stage(300, 390, .sleeping), stage(390, 420, .unknown)], originApp: "com.sec.android.app.shealth", deviceName: "Samsung Galaxy Watch 6", recordingMethod: "automatic")
        return Entry(id: "hc:sleep-rich", date: end, kind: "수면", value: 7.5, bedTime: start, wakeTime: end, awakeMinutes: 30, sleep: details)
    }
    func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    func testPartialStagesReportCoverageAndKeepGapsUnclassified() throws {
        let entry = richEntry(); try CareBackup(entries: [entry]).validate()
        let analysis = try XCTUnwrap(entry.sleepAnalysis)
        XCTAssertEqual(analysis.sessionMinutes, 480, accuracy: 0.001); XCTAssertEqual(analysis.sleepMinutes, 450, accuracy: 0.001)
        XCTAssertEqual(analysis.minutes(for: .awake), 30, accuracy: 0.001); XCTAssertEqual(analysis.minutes(for: .light), 120, accuracy: 0.001)
        XCTAssertEqual(analysis.minutes(for: .deep), 60, accuracy: 0.001); XCTAssertEqual(analysis.minutes(for: .rem), 90, accuracy: 0.001)
        XCTAssertEqual(analysis.minutes(for: .sleeping), 90, accuracy: 0.001); XCTAssertEqual(analysis.minutes(for: .unknown), 30, accuracy: 0.001)
        XCTAssertEqual(analysis.coverage, 390.0 / 480, accuracy: 0.001); XCTAssertEqual(analysis.unclassifiedMinutes, 90, accuracy: 0.001)
        XCTAssertEqual(analysis.efficiency, 450.0 / 480, accuracy: 0.001); XCTAssertTrue(analysis.hasStages)
        XCTAssertTrue(analysis.isGalaxyWatch); XCTAssertFalse(analysis.needsSourceConfirmation); XCTAssertTrue(analysis.sourceLabel.contains("Galaxy Watch"))
        XCTAssertEqual(analysis.recordingMethodLabel, "자동 기록")
    }
    func testNoStageOrDeviceDataDoesNotInventWatchOrMeasurements() throws {
        var entry = richEntry(); entry.source = "health-connect:peer"; entry.value = 8; entry.awakeMinutes = 0
        entry.sleep = SleepDetails(stages: [], originApp: "com.sec.android.app.shealth", recordingMethod: "unknown")
        try CareBackup(entries: [entry]).validate()
        var analysis = try XCTUnwrap(entry.sleepAnalysis)
        XCTAssertFalse(analysis.hasStages); XCTAssertFalse(analysis.isGalaxyWatch); XCTAssertTrue(analysis.needsSourceConfirmation)
        XCTAssertTrue(analysis.sourceLabel.contains("출처 확인 필요")); XCTAssertEqual(analysis.coverage, 0); XCTAssertEqual(analysis.unclassifiedMinutes, 480)
        entry.sleep?.deviceName = "Samsung SM-R930"; analysis = try XCTUnwrap(entry.sleepAnalysis)
        XCTAssertFalse(analysis.isGalaxyWatch, "An app or a model code alone must not be identified as a Galaxy Watch")
        entry.sleep?.stages = [SleepStage(start: entry.bedTime!, end: entry.wakeTime!, type: .unknown)]
        analysis = try XCTUnwrap(entry.sleepAnalysis); XCTAssertFalse(analysis.hasStages); XCTAssertEqual(analysis.coverage, 0); XCTAssertEqual(analysis.unclassifiedMinutes, 480)
        entry.source = nil; entry.sleep = nil; entry.awakeMinutes = 30; entry.value = 7.5
        analysis = try XCTUnwrap(entry.sleepAnalysis); XCTAssertEqual(analysis.sourceLabel, "직접 기록"); XCTAssertFalse(analysis.needsSourceConfirmation)
        XCTAssertFalse(analysis.hasStages); XCTAssertEqual(analysis.awakeMinutes, 30); XCTAssertEqual(analysis.unclassifiedMinutes, 480)
    }
    func testInvalidStagesMetadataAndMismatchedDurationsAreRejected() throws {
        let original = richEntry()
        var invalid = original; invalid.sleep!.stages[1].start = original.bedTime!.addingTimeInterval(29 * 60)
        XCTAssertThrowsError(try CareBackup(entries: [invalid]).validate())
        invalid = original; invalid.sleep!.stages[0].start = original.bedTime!.addingTimeInterval(-1)
        XCTAssertThrowsError(try CareBackup(entries: [invalid]).validate())
        invalid = original; invalid.sleep!.stages[0].end = original.sleep!.stages[0].start
        XCTAssertThrowsError(try CareBackup(entries: [invalid]).validate())
        invalid = original; invalid.sleep!.stages[0].start = Date(timeIntervalSince1970: .infinity)
        XCTAssertThrowsError(try CareBackup(entries: [invalid]).validate())
        invalid = original; invalid.sleep!.stages = Array(repeating: original.sleep!.stages[0], count: 2049)
        XCTAssertThrowsError(try CareBackup(entries: [invalid]).validate())
        invalid = original; invalid.sleep!.deviceName = String(repeating: "x", count: 201)
        XCTAssertThrowsError(try CareBackup(entries: [invalid]).validate())
        invalid = original; invalid.sleep!.originApp = String(repeating: "x", count: 201)
        XCTAssertThrowsError(try CareBackup(entries: [invalid]).validate())
        invalid = original; invalid.sleep!.recordingMethod = "made-up-measurement"
        XCTAssertThrowsError(try CareBackup(entries: [invalid]).validate())
        invalid = original; invalid.awakeMinutes = 31; invalid.value = (480 - 31) / 60
        XCTAssertThrowsError(try CareBackup(entries: [invalid]).validate(), "An explicit awake stage must match the existing awake total")
        invalid = original; invalid.value = 7.6
        XCTAssertThrowsError(try CareBackup(entries: [invalid]).validate())
        invalid = original; invalid.kind = "체중"
        XCTAssertThrowsError(try CareBackup(entries: [invalid]).validate())
        invalid = original; invalid.bedTime = nil
        XCTAssertThrowsError(try CareBackup(entries: [invalid]).validate())
        let goodData = try CareBackup(entries: [original]).encoded(), text = String(decoding: goodData, as: UTF8.self)
        XCTAssertThrowsError(try CareBackup.decode(Data(text.replacingOccurrences(of: "\"deep\"", with: "\"unsupported-stage\"").utf8)))
    }
    func testLegacyBackupsAndOptionalRichMetadataRoundTrip() throws {
        let end = Int(Date().timeIntervalSince1970 * 1000) - 1000
        let old = try CareBackup.decode(Data("{\"version\":2,\"entries\":[{\"id\":\"old-sleep\",\"date\":\(end),\"kind\":\"수면\",\"value\":6.5,\"note\":\"\"}]}".utf8))
        XCTAssertNil(old.entries[0].sleep); XCTAssertNil(old.entries[0].sleepAnalysis); XCTAssertEqual(old.entries[0].value, 6.5)
        let legacyArray = try JSONEncoder().encode([Entry(kind: "수면", value: 7)])
        XCTAssertNil(try CareBackup.decode(legacyArray).entries[0].sleep)
        let original = richEntry(), data = try CareBackup(entries: [original]).encoded(), restored = try CareBackup.decode(data).entries[0]
        XCTAssertEqual(restored.sleep?.originApp, original.sleep?.originApp); XCTAssertEqual(restored.sleep?.deviceName, original.sleep?.deviceName)
        XCTAssertEqual(restored.sleep?.recordingMethod, original.sleep?.recordingMethod); XCTAssertEqual(restored.sleep?.stages.count, 6)
        for (saved, decoded) in zip(original.sleep!.stages, restored.sleep!.stages) {
            XCTAssertEqual(saved.type, decoded.type); XCTAssertEqual(saved.start.timeIntervalSince1970, decoded.start.timeIntervalSince1970, accuracy: 0.001)
            XCTAssertEqual(saved.end.timeIntervalSince1970, decoded.end.timeIntervalSince1970, accuracy: 0.001)
        }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]), records = try XCTUnwrap(json["entries"] as? [[String: Any]])
        let details = try XCTUnwrap(records[0]["sleep"] as? [String: Any]), stages = try XCTUnwrap(details["stages"] as? [[String: Any]])
        XCTAssertGreaterThan(try XCTUnwrap(stages[0]["start"] as? Double), 100_000_000_000, "Wire dates must use Unix milliseconds")
        XCTAssertEqual(json["version"] as? Int, 3)
    }
    @MainActor func testMalformedStoredStagesStopReadingAndPreserveOriginalFile() throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        var malformed = richEntry(); malformed.sleep!.stages[1].start = malformed.bedTime!
        let raw = try CareBackup(entries: [malformed, Entry(kind: "체중", value: 70)]).encoded()
        let url = folder.appendingPathComponent("care-v3.json"); try raw.write(to: url)
        let journal = Journal(directory: folder)
        XCTAssertNotNil(journal.notice); XCTAssertTrue(journal.entries.isEmpty)
        XCTAssertFalse(journal.save(Entry(kind: "물", value: 200)))
        XCTAssertEqual(try Data(contentsOf: url), raw, "A failed read must never replace or partially rewrite the stored file")
    }
    @MainActor func testRepeatedHealthSyncUpdatesSleepMetadataAndRejectsMalformedSnapshotAtomically() throws {
        let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let journal = Journal(directory: folder); XCTAssertTrue(journal.save(Entry(kind: "체중", value: 70)))
        let pair = SyncPair(version: 1, host: "192.168.1.20", port: 8766, peer: UUID().uuidString, token: String(repeating: "a", count: 43), fingerprint: String(repeating: "b", count: 64)), now = Date()
        var entry = richEntry(), snapshot = HealthSnapshot(version: 1, peer: pair.peer, generatedAt: now, windowStart: dayOffset(-29), kinds: ["수면"], entries: [])
        snapshot.entries = [entry]; _ = try journal.applyHealth(snapshot, pair: pair)
        let stableID = try XCTUnwrap(journal.latest("수면")?.id)
        _ = try journal.applyHealth(snapshot, pair: pair); XCTAssertEqual(journal.entries.count, 2)
        entry.sleep!.deviceName = "Samsung SM-R930"; entry.sleep!.recordingMethod = "manual"; snapshot.entries = [entry]
        _ = try journal.applyHealth(snapshot, pair: pair)
        XCTAssertEqual(journal.entries.count, 2); XCTAssertEqual(journal.latest("수면")?.id, stableID)
        XCTAssertEqual(journal.latest("수면")?.sleep?.deviceName, "Samsung SM-R930"); XCTAssertEqual(journal.latest("수면")?.sleep?.recordingMethod, "manual")
        let before = journal.entries, url = folder.appendingPathComponent("care-v3.json"), beforeData = try Data(contentsOf: url)
        snapshot.entries[0].sleep!.stages[0].end = entry.wakeTime!
        XCTAssertThrowsError(try journal.applyHealth(snapshot, pair: pair))
        XCTAssertEqual(journal.entries, before); XCTAssertEqual(try Data(contentsOf: url), beforeData)
        let restored = try XCTUnwrap(Journal(directory: folder).latest("수면"))
        XCTAssertEqual(restored.id, stableID); XCTAssertEqual(restored.sleep?.deviceName, "Samsung SM-R930"); XCTAssertEqual(restored.sleep?.stages.count, 6)
    }
}
