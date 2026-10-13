import XCTest
@testable import OnCare

final class PersonalShareTests: XCTestCase {
    func testSelectionWindowAndPrivateFields() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1800000000)
        let recent = calendar.startOfDay(for: now).addingTimeInterval(100)
        let entries = [Entry(date: recent, kind: "운동", value: 20, note: "PRIVATE NOTE", source: "PRIVATE DEVICE"), Entry(date: now.addingTimeInterval(-31*86400), kind: "운동", value: 99), Entry(date: now.addingTimeInterval(1000), kind: "운동", value: 99), Entry(date: recent, kind: "체중", value: 70), Entry(date: recent, kind: "마음", value: 2)]
        let text = PersonalShareReport.text(entries: entries, kinds: ["운동","수면"], days: 7, name: " \n민지\n ", now: now, calendar: calendar)
        XCTAssertTrue(text.contains("운동 합계: 20 분")); XCTAssertTrue(text.contains("수면: 기록 없음")); XCTAssertTrue(text.contains("이름: 민지"))
        for secret in ["PRIVATE", "체중", "마음", "99", "oncare1:"] { XCTAssertFalse(text.contains(secret)) }
    }
    func testDailyLastMeansAndCalendarBoundary() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12))!
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
        let entries = [Entry(date: start.addingTimeInterval(-1), kind: "수면", value: 20), Entry(date: start, kind: "수면", value: 2), Entry(date: start.addingTimeInterval(100), kind: "수면", value: 8), Entry(date: now, kind: "수면", value: 6)]
        let text = PersonalShareReport.text(entries: entries, kinds: ["수면"], days: 7, now: now, calendar: calendar)
        XCTAssertTrue(text.contains("수면 평균: 7 시간 · 2일 기록"))
    }
    func testQRPayloadUsesExistingStrictValidator() throws {
        let pair = SyncPair(version: 1, host: "192.168.1.4", port: 8766, peer: UUID().uuidString, token: String(repeating: "a", count: 43), fingerprint: String(repeating: "b", count: 64))
        let raw = try JSONEncoder().encode(pair).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(try SyncPair.decode("oncare1:" + raw), pair)
        XCTAssertThrowsError(try SyncPair.decode("https://example.com")); XCTAssertThrowsError(try SyncPair.decode("oncare1:" + String(repeating: "a", count: 2049)))
        var bad = pair; bad.host = "8.8.8.8"; XCTAssertThrowsError(try bad.validate())
    }
    func testInstalledVersion() { XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, "3.13.0"); XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String, "22") }
}
