import XCTest
@testable import OnCare

@MainActor final class SleepTrackingTests: XCTestCase {
    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func testSleepSessionRestoresAfterAppExitAndExcludesLatencyAndAwake() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let start = Date().addingTimeInterval(-12 * 3600), end = start.addingTimeInterval(8 * 3600)
        let timer = SleepTrackingStore(directory: dir, now: start)
        try timer.start(at: start); try timer.checkpoint(at: start.addingTimeInterval(30 * 60))
        let restored = SleepTrackingStore(directory: dir, now: end)
        XCTAssertEqual(restored.session?.id, timer.session?.id); XCTAssertNil(restored.issue)
        let journal = Journal(directory: dir)
        _ = try restored.finish(in: journal, latency: 15, awake: 30, at: end)
        XCTAssertNil(restored.session); XCTAssertEqual(journal.entries.count, 1)
        let entry = try XCTUnwrap(journal.entries.first)
        XCTAssertEqual(entry.value, 7.25, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(entry.bedTime).timeIntervalSince1970, start.addingTimeInterval(15 * 60).timeIntervalSince1970, accuracy: 0.001); XCTAssertEqual(try XCTUnwrap(entry.wakeTime).timeIntervalSince1970, end.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertNil(entry.sleep); XCTAssertNil(entry.source)
        XCTAssertEqual(Journal(directory: dir).entries.first?.id, entry.id)
    }
    func testShortAndInvalidResultsKeepTheStartedSession() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let start = Date().addingTimeInterval(-12 * 3600), timer = SleepTrackingStore(directory: dir, now: start), journal = Journal(directory: dir)
        try timer.start(at: start)
        XCTAssertThrowsError(try timer.finish(in: journal, latency: 0, awake: 0, at: start.addingTimeInterval(30)))
        for value in [-1.0, 91, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try timer.finish(in: journal, latency: value, awake: 0, at: start.addingTimeInterval(8 * 3600)))
        }
        XCTAssertThrowsError(try timer.finish(in: journal, latency: 0, awake: 999, at: start.addingTimeInterval(8 * 3600)))
        XCTAssertNotNil(timer.session); XCTAssertNil(timer.session?.finishedAt); XCTAssertTrue(journal.entries.isEmpty)
    }
    func testSaveFailureFreezesResultAndRetryIgnoresChangedInputs() throws {
        let timerDir = try folder(), failedDir = try folder(), goodDir = try folder()
        defer { for dir in [timerDir, failedDir, goodDir] { try? FileManager.default.removeItem(at: dir) } }
        try FileManager.default.createDirectory(at: failedDir.appendingPathComponent("care-v3.json"), withIntermediateDirectories: false)
        let start = Date().addingTimeInterval(-12 * 3600), end = start.addingTimeInterval(8 * 3600)
        let timer = SleepTrackingStore(directory: timerDir, now: start); try timer.start(at: start)
        XCTAssertThrowsError(try timer.finish(in: Journal(directory: failedDir), latency: 15, awake: 30, at: end))
        XCTAssertEqual(timer.session?.finishedAt, end)
        let restored = SleepTrackingStore(directory: timerDir, now: end.addingTimeInterval(600)), journal = Journal(directory: goodDir)
        _ = try restored.finish(in: journal, latency: 0, awake: 0, at: end.addingTimeInterval(600))
        XCTAssertEqual(try XCTUnwrap(journal.entries.first).date.timeIntervalSince1970, end.timeIntervalSince1970, accuracy: 0.001); XCTAssertEqual(try XCTUnwrap(journal.entries.first).value, 7.25, accuracy: 0.001)
        XCTAssertNil(restored.session)
    }
    func testInterruptedCleanupDoesNotDuplicateAnAlreadySavedSleep() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let start = Date().addingTimeInterval(-12 * 3600), end = start.addingTimeInterval(8 * 3600)
        let timer = SleepTrackingStore(directory: dir, now: start), journal = Journal(directory: dir)
        try timer.start(at: start)
        let id = try XCTUnwrap(timer.session?.id)
        XCTAssertTrue(journal.save(Entry(id: id, date: end, kind: "수면", value: 8, bedTime: start, wakeTime: end, awakeMinutes: 0)))
        let recovered = SleepTrackingStore(directory: dir, now: start.addingTimeInterval(-60))
        XCTAssertNotNil(recovered.issue)
        _ = try recovered.finish(in: journal, latency: 0, awake: 0, at: start.addingTimeInterval(-60))
        XCTAssertEqual(journal.entries.count, 1); XCTAssertNil(recovered.session)
    }
    func testClockRollbackAndExpiredSessionRequireAnExplicitReset() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let start = Date().addingTimeInterval(-12 * 3600), timer = SleepTrackingStore(directory: dir, now: start)
        try timer.start(at: start); try timer.checkpoint(at: start.addingTimeInterval(600))
        XCTAssertThrowsError(try timer.checkpoint(at: start.addingTimeInterval(599)))
        XCTAssertThrowsError(try timer.finish(in: Journal(directory: dir), latency: 0, awake: 0, at: start.addingTimeInterval(25 * 3600)))
        XCTAssertNotNil(timer.session); try timer.reset(); XCTAssertNil(timer.session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("sleep-session-v1.json").path))
    }
    func testCorruptSleepStateIsPreservedUntilExplicitReset() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("sleep-session-v1.json"), original = Data("broken sleep state".utf8)
        try original.write(to: file)
        let timer = SleepTrackingStore(directory: dir)
        XCTAssertNotNil(timer.issue); XCTAssertNil(timer.session); XCTAssertThrowsError(try timer.start())
        XCTAssertEqual(try Data(contentsOf: file), original)
        try timer.reset(); XCTAssertNil(timer.issue); try timer.start(); XCTAssertNotNil(timer.session)
    }
    func testMidnightPatternUsesShortClockSpanAndNeedsTwoDays() {
        XCTAssertEqual(SleepPatternSummary.clockSpan([1435.0, 5.0]), 10)
        XCTAssertEqual(SleepPatternSummary.clockSpan([420.0, 440.0, 430.0]), 20)
        XCTAssertNil(SleepPatternSummary.clockSpan([1380.0]))
    }
    func testSevenDayPatternKeepsLastRecordAndExcludesOldAndFutureDays() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
        func date(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: now)! }
        let records = [Entry(id: "a", date: date(-1), kind: "수면", value: 4), Entry(id: "z", date: date(-1), kind: "수면", value: 8),
                       Entry(date: date(-6), kind: "수면", value: 6), Entry(date: date(-7), kind: "수면", value: 99),
                       Entry(date: date(1), kind: "수면", value: 99), Entry(date: date(-1), kind: "운동", value: 999)]
        let summary = SleepPatternSummary.analyze(records, now: now, calendar: calendar)
        XCTAssertEqual(summary.entries.count, 2); XCTAssertEqual(summary.meanHours, 7)
        XCTAssertNil(summary.bedtimeSpan); XCTAssertNil(summary.wakeSpan)
        XCTAssertEqual(SleepPatternSummary.analyze(Array(records.reversed()), now: now, calendar: calendar).meanHours, 7)
    }
}
