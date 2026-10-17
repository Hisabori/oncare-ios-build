import XCTest
@testable import OnCare

final class IntelligencePolicyTests: XCTestCase {
    func testArticleBudgetAndOutputValidation() throws {
        XCTAssertEqual(IntelligencePolicy.article("  \n"), "")
        XCTAssertEqual(IntelligencePolicy.article(String(repeating: "가", count: 3000)).count, 2700)
        XCTAssertEqual(try IntelligencePolicy.validated("  한 줄\n다음 줄  "), "한 줄\n다음 줄")
        XCTAssertThrowsError(try IntelligencePolicy.validated("  "))
        XCTAssertThrowsError(try IntelligencePolicy.validated("숨김\u{0000}문자"))
        XCTAssertThrowsError(try IntelligencePolicy.validated(String(repeating: "가", count: 4001)))
    }
    @MainActor func testThirtyDayContextExcludesFutureAndPrivateText() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = Journal(directory: directory)
        let now = Date()
        XCTAssertTrue(journal.save(Entry(date: now.addingTimeInterval(-60), kind: "운동", value: 20, note: "PRIVATE")))
        XCTAssertTrue(journal.save(Entry(date: dayOffset(-15, from: now), kind: "운동", value: 30)))
        XCTAssertTrue(journal.save(Entry(date: dayOffset(-35, from: now), kind: "운동", value: 40)))
        XCTAssertTrue(journal.save(Entry(date: now.addingTimeInterval(3600), kind: "운동", value: 50)))
        let short = IntelligenceContext.snapshot(journal, now: now)
        let long = IntelligenceContext.snapshot(journal, now: now, days: 30)
        XCTAssertTrue(short.contains("운동 합계: 20분"))
        XCTAssertTrue(long.contains("운동 합계: 50분"))
        XCTAssertTrue(long.contains("2/30일"))
        XCTAssertFalse(long.contains("PRIVATE"))
        XCTAssertEqual(IntelligencePolicy.period(10000), 7)
    }
    @MainActor func testMissingDaysAreNotZeroMoodValues() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = Journal(directory: directory)
        let now = Date()
        XCTAssertTrue(journal.save(Entry(date: now.addingTimeInterval(-60), kind: "마음", value: 4)))
        let context = IntelligenceContext.snapshot(journal, now: now, days: 30)
        XCTAssertTrue(context.contains("마음 평균: 4/5"))
        XCTAssertTrue(context.contains("수면 평균: 기록 없음"))
    }
}
