import XCTest
@testable import OnCare

@MainActor final class FakeCareNotifications: CareNotificationCenter {
    var allowed = true
    var fail = false
    var removals = 0
    var schedules = 0
    func authorize() async throws -> Bool { allowed }
    func schedule(hour: Int, minute: Int) async throws { if fail { throw URLError(.cannotConnectToHost) }; schedules += 1 }
    func remove() { removals += 1 }
}
final class BugAndSyncTests: XCTestCase {
    func testNumericGroupingAndFileCancellation() {
        XCTAssertEqual(inputNumber("1,500"), 1500)
        XCTAssertEqual(inputNumber(" 72.45 \n"), 72.45)
        XCTAssertEqual(inputNumber("1,000.5"), 1000.5)
        for value in ["1,5", "15,00", "1,500,", "nan", "inf", ""] { XCTAssertNil(inputNumber(value)) }
        XCTAssertTrue(isFileSelectionCancelled(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)))
        XCTAssertFalse(isFileSelectionCancelled(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)))
    }
    @MainActor func testFailedReminderChangePreservesPreviousSchedule() async throws {
        let name = UUID().uuidString; let defaults = UserDefaults(suiteName: name)!; defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "reminder-enabled"); defaults.set(21, forKey: "reminder-hour")
        let center = FakeCareNotifications(); center.fail = true
        do { _ = try await ReminderScheduler.update(enabled: true, hour: 8, minute: 30, defaults: defaults, center: center); XCTFail("Expected a scheduling failure") } catch {}
        XCTAssertTrue(defaults.bool(forKey: "reminder-enabled")); XCTAssertEqual(defaults.integer(forKey: "reminder-hour"), 21); XCTAssertEqual(center.removals, 0)
        center.fail = false
        let success = try await ReminderScheduler.update(enabled: true, hour: 8, minute: 30, defaults: defaults, center: center)
        XCTAssertTrue(success); XCTAssertEqual(defaults.integer(forKey: "reminder-hour"), 8); XCTAssertEqual(center.schedules, 1)
        center.allowed = false
        let denied = try await ReminderScheduler.update(enabled: true, hour: 9, minute: 0, defaults: defaults, center: center)
        XCTAssertFalse(denied); XCTAssertFalse(defaults.bool(forKey: "reminder-enabled")); XCTAssertEqual(center.removals, 1)
    }
    @MainActor func testDayChangeOnlyRefreshesWhenNeeded() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
        let journal = Journal(directory: directory); journal.refreshCalendar(now: dayOffset(-2)); let revision = journal.calendarRevision
        journal.refreshCalendar(now: dayOffset(-2).addingTimeInterval(60)); XCTAssertEqual(journal.calendarRevision, revision)
        journal.refreshCalendar(now: dayOffset(-1)); XCTAssertEqual(journal.calendarRevision, revision + 1)
    }
    func pair() -> SyncPair { SyncPair(version: 1, host: "192.168.1.20", port: 8766, peer: "F03D4D52-10FD-41E3-BCB7-6F5A27D63C29", token: String(repeating: "a", count: 43), fingerprint: String(repeating: "b", count: 64)) }
    func testPairCodeRejectsPublicHostsAndBadCredentials() throws {
        let pair = pair(); let raw = try JSONEncoder().encode(pair).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(try SyncPair.decode("oncare1:" + raw), pair)
        for host in ["8.8.8.8", "127.0.0.1", "192.168.001.1", "172.32.0.1", "example.com", "192.168.1.999"] { var invalid = pair; invalid.host = host; XCTAssertThrowsError(try invalid.validate()) }
        var invalid = pair; invalid.token = "short"; XCTAssertThrowsError(try invalid.validate())
    }
    @MainActor func testHealthSyncUpdatesDeletesAndKeepsManualRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
        let journal = Journal(directory: directory); XCTAssertTrue(journal.save(Entry(kind: "수면", value: 6)))
        let pair = pair(), now = Date(); let date = now.addingTimeInterval(-60)
        var snapshot = HealthSnapshot(version: 1, peer: pair.peer, generatedAt: now, windowStart: dayOffset(-29), kinds: ["체중", "걸음"], entries: [Entry(id: "hc:weight", date: date, kind: "체중", value: 72), Entry(id: "hc:steps", date: date, kind: "걸음", value: 3210)])
        XCTAssertEqual(try journal.applyHealth(snapshot, pair: pair), 2); XCTAssertEqual(try journal.applyHealth(snapshot, pair: pair), 2); XCTAssertEqual(journal.entries.count, 3)
        snapshot.entries[0].value = 71.5; _ = try journal.applyHealth(snapshot, pair: pair); XCTAssertEqual(journal.latest("체중")?.value, 71.5); XCTAssertEqual(journal.entries.count, 3)
        let before = journal.entries; snapshot.peer = UUID().uuidString; XCTAssertThrowsError(try journal.applyHealth(snapshot, pair: pair)); XCTAssertEqual(journal.entries, before)
        snapshot.peer = pair.peer; snapshot.kinds = ["체중"]; snapshot.entries = []; _ = try journal.applyHealth(snapshot, pair: pair)
        XCTAssertNil(journal.latest("체중")); XCTAssertEqual(journal.latest("걸음")?.value, 3210); XCTAssertEqual(journal.latest("수면")?.value, 6)
        let reloaded = Journal(directory: directory).entries; XCTAssertEqual(reloaded.count, journal.entries.count)
        for (saved, loaded) in zip(journal.entries, reloaded) { XCTAssertEqual(saved.id, loaded.id); XCTAssertEqual(saved.kind, loaded.kind); XCTAssertEqual(saved.value, loaded.value); XCTAssertEqual(saved.source, loaded.source); XCTAssertEqual(saved.date.timeIntervalSince1970, loaded.date.timeIntervalSince1970, accuracy: 0.001) }
    }
    func testSleepCalculationCrossesMidnightAndRejectsInvalidIntervals() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let wake = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 7))!
        let plan = SleepPlan(); let bedtime = plan.bedtime(wake: wake)
        let parts = calendar.dateComponents([.day, .hour, .minute], from: bedtime)
        XCTAssertEqual(parts.day, 11); XCTAssertEqual(parts.hour, 23); XCTAssertEqual(parts.minute, 15)
        XCTAssertEqual(SleepPlan.measuredHours(start: wake.addingTimeInterval(-8 * 3600), end: wake, awake: 30), 7.5)
        XCTAssertNil(SleepPlan.measuredHours(start: wake, end: wake, awake: 0)); XCTAssertNil(SleepPlan.measuredHours(start: wake.addingTimeInterval(-3600), end: wake, awake: 60)); XCTAssertNil(SleepPlan.measuredHours(start: wake.addingTimeInterval(-25 * 3600), end: wake, awake: 0))
        let entry = Entry(date: wake, kind: "수면", value: 7.5, bedTime: wake.addingTimeInterval(-8 * 3600), wakeTime: wake, awakeMinutes: 30)
        XCTAssertNoThrow(try CareBackup(entries: [entry]).validate(now: wake.addingTimeInterval(1)))
        var invalid = entry; invalid.value = 8; XCTAssertThrowsError(try CareBackup(entries: [invalid]).validate(now: wake.addingTimeInterval(1)))
    }
}
