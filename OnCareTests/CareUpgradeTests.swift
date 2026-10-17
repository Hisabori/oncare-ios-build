import XCTest
@testable import OnCare
final class CareUpgradeTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    func testMoodContextIgnoresFutureInvalidAndDuplicateDays() {
        let now = Date(timeIntervalSince1970: 1800000000)
        let values = [Entry(date: now.addingTimeInterval(-10), kind: "마음", value: 2), Entry(date: now.addingTimeInterval(-20), kind: "마음", value: 4), Entry(date: now.addingTimeInterval(10), kind: "마음", value: 5), Entry(date: now, kind: "마음", value: .nan), Entry(date: now, kind: "물", value: 500)]
        let result = CareUpgrade.moodContext(values, now: now, calendar: calendar)
        XCTAssertEqual(result.days, 1); XCTAssertEqual(result.latest, 2)
        XCTAssertEqual(CareUpgrade.moodContext([], now: now, calendar: calendar).days, 0)
    }
    func testMedicationPhaseNeverInfersMissedDose() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 10, minute: 0))!
        XCTAssertEqual(CareUpgrade.medicationPhase(hour: 9, minute: 0, checked: false, now: now, calendar: calendar), "시간 지남 · 확인 전")
        XCTAssertEqual(CareUpgrade.medicationPhase(hour: 11, minute: 0, checked: false, now: now, calendar: calendar), "예정 · 확인 전")
        XCTAssertEqual(CareUpgrade.medicationPhase(hour: 9, minute: 0, checked: true, now: now, calendar: calendar), "확인 완료")
    }
    func testCoverageRequiresFullEpochAndIsBounded() {
        XCTAssertNil(CareUpgrade.coverage(analyzed: 0, measuredSeconds: 29))
        XCTAssertNil(CareUpgrade.coverage(analyzed: -1, measuredSeconds: 60))
        XCTAssertEqual(CareUpgrade.coverage(analyzed: 1, measuredSeconds: 60), 0.5)
        XCTAssertEqual(CareUpgrade.coverage(analyzed: 3, measuredSeconds: 60), 1)
    }
}
