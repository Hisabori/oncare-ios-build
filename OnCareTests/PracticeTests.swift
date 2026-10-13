import XCTest
@testable import OnCare

final class PracticeTests: XCTestCase {
    func directory() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }
    func write(_ session: WorkoutSession, to directory: URL) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(session).write(to: directory.appendingPathComponent("workout-session-v1.json"))
    }
    @MainActor func testTimerRestoresRunningAndExcludesPausedTime() throws {
        let d = try directory(); defer { try? FileManager.default.removeItem(at: d) }
        let start = Date().addingTimeInterval(-86400)
        let store = WorkoutTimerStore(directory: d, now: start)
        try store.start(type: "걷기", goal: 20, at: start)
        try store.checkpoint(at: start.addingTimeInterval(45))
        let restored = WorkoutTimerStore(directory: d, now: start.addingTimeInterval(90))
        XCTAssertNil(restored.issue); XCTAssertEqual(try restored.session!.elapsed(at: start.addingTimeInterval(90)), 90, accuracy: 0.001)
        let id = restored.session!.id
        try restored.pause(at: start.addingTimeInterval(120))
        let paused = WorkoutTimerStore(directory: d, now: start.addingTimeInterval(3600))
        XCTAssertFalse(paused.session!.running); XCTAssertEqual(try paused.session!.elapsed(at: start.addingTimeInterval(3600)), 120, accuracy: 0.001)
        try paused.resume(at: start.addingTimeInterval(3600))
        XCTAssertEqual(try paused.session!.elapsed(at: start.addingTimeInterval(3630)), 150, accuracy: 0.001)
        let journal = Journal(directory: d)
        _ = try paused.finish(in: journal, at: start.addingTimeInterval(3660))
        XCTAssertNil(paused.session); XCTAssertEqual(journal.entries.count, 1); XCTAssertEqual(journal.entries[0].id, id)
        XCTAssertEqual(journal.entries[0].value, 3, accuracy: 0.001); XCTAssertEqual(journal.entries[0].type, "걷기")
        XCTAssertNil(WorkoutTimerStore(directory: d).session)
    }
    @MainActor func testShortTimerDoesNotSaveOrDiscardAndCorruptFileIsPreserved() throws {
        let d = try directory(); defer { try? FileManager.default.removeItem(at: d) }
        let now = Date().addingTimeInterval(-1000), store = WorkoutTimerStore(directory: d, now: now), journal = Journal(directory: d)
        try store.start(type: "근력", goal: 10, at: now)
        XCTAssertThrowsError(try store.finish(in: journal, at: now.addingTimeInterval(59)))
        XCTAssertTrue(journal.entries.isEmpty); XCTAssertTrue(store.session!.running)
        try store.reset()
        let url = d.appendingPathComponent("workout-session-v1.json"), bad = Data("{broken-session".utf8)
        try bad.write(to: url)
        let corrupt = WorkoutTimerStore(directory: d)
        XCTAssertNotNil(corrupt.issue); XCTAssertThrowsError(try corrupt.start(type: "걷기", goal: 20))
        XCTAssertEqual(try Data(contentsOf: url), bad)
        try corrupt.reset(); try corrupt.start(type: "스트레칭", goal: 10)
        XCTAssertNotNil(corrupt.session)
    }
    @MainActor func testFailedRecordSaveFreezesResultAndRetryKeepsSameID() throws {
        let d = try directory(); defer { try? FileManager.default.removeItem(at: d) }
        let start = Date().addingTimeInterval(-3600)
        try Data("not-json".utf8).write(to: d.appendingPathComponent("care-v3.json"))
        let broken = Journal(directory: d), store = WorkoutTimerStore(directory: d, now: start)
        try store.start(type: "러닝", goal: 30, at: start)
        let id = store.session!.id
        XCTAssertThrowsError(try store.finish(in: broken, at: start.addingTimeInterval(120)))
        XCTAssertNotNil(store.session?.finishedAt); XCTAssertEqual(store.session?.elapsedSeconds, 120)
        XCTAssertTrue(FileManager.default.fileExists(atPath: d.appendingPathComponent("workout-session-v1.json").path))
        try FileManager.default.removeItem(at: d.appendingPathComponent("care-v3.json"))
        let healthy = Journal(directory: d), restored = WorkoutTimerStore(directory: d, now: start.addingTimeInterval(600))
        _ = try restored.finish(in: healthy, at: start.addingTimeInterval(600))
        XCTAssertEqual(healthy.entries.count, 1); XCTAssertEqual(healthy.entries[0].id, id); XCTAssertEqual(healthy.entries[0].value, 2)
    }
    @MainActor func testRecoveryAfterRecordWriteDoesNotCreateDuplicate() throws {
        let d = try directory(); defer { try? FileManager.default.removeItem(at: d) }
        let start = Date().addingTimeInterval(-3600), finish = start.addingTimeInterval(600)
        let session = WorkoutSession(type: "걷기", goalMinutes: 10, createdAt: start, checkpointAt: finish, elapsedSeconds: 600, finishedAt: finish)
        try write(session, to: d)
        let journal = Journal(directory: d)
        XCTAssertTrue(journal.save(Entry(id: session.id, date: finish, kind: "운동", value: 10, type: "걷기")))
        let restored = WorkoutTimerStore(directory: d)
        XCTAssertTrue(try restored.finish(in: journal).contains("중복"))
        XCTAssertEqual(journal.entries.count, 1); XCTAssertEqual(journal.entries[0].value, 10); XCTAssertNil(restored.session)
    }
    @MainActor func testTimerRejectsClockRollbackAndMoreThan24Hours() throws {
        let d = try directory(); defer { try? FileManager.default.removeItem(at: d) }
        let start = Date().addingTimeInterval(-90000), store = WorkoutTimerStore(directory: d, now: start)
        try store.start(type: "걷기", goal: 10, at: start)
        store.observe(at: start.addingTimeInterval(30)); store.observe(at: start.addingTimeInterval(20))
        XCTAssertEqual(store.issue, PracticeError.clockChanged.message)
        XCTAssertThrowsError(try store.pause(at: start.addingTimeInterval(20)))
        store.observe(at: start.addingTimeInterval(40)); XCTAssertNil(store.issue)
        XCTAssertNoThrow(try store.session!.elapsed(at: start.addingTimeInterval(86400)))
        XCTAssertThrowsError(try store.session!.elapsed(at: start.addingTimeInterval(86401)))
        var damaged = store.session!; damaged.elapsedSeconds = 100
        XCTAssertThrowsError(try damaged.validate(at: start.addingTimeInterval(100)))
        damaged.segmentStartedAt = start.addingTimeInterval(30); damaged.checkpointAt = start.addingTimeInterval(120)
        XCTAssertThrowsError(try damaged.validate(at: start.addingTimeInterval(120)), "Accumulated time cannot include time from the current running segment")
        store.observe(at: start.addingTimeInterval(86401))
        XCTAssertNil(store.issue); XCTAssertFalse(store.session!.running); XCTAssertEqual(store.session!.elapsedSeconds, 86400)
        XCTAssertThrowsError(try store.resume(at: start.addingTimeInterval(86402)))
        let journal = Journal(directory: d); _ = try store.finish(in: journal, at: start.addingTimeInterval(86403))
        XCTAssertEqual(journal.entries.first?.value, 1440)
    }
    @MainActor func testSavedRecordAllowsCleanupEvenAfterClockRollback() throws {
        let d = try directory(); defer { try? FileManager.default.removeItem(at: d) }
        let start = Date().addingTimeInterval(-3600), finish = start.addingTimeInterval(600)
        let session = WorkoutSession(type: "걷기", goalMinutes: 10, createdAt: start, checkpointAt: finish, elapsedSeconds: 600, finishedAt: finish)
        // Simulate a completed journal write with session cleanup interrupted or unsuccessful.
        try write(session, to: d)
        let journal = Journal(directory: d)
        XCTAssertTrue(journal.save(Entry(id: session.id, date: finish, kind: "운동", value: 10, type: "걷기")))
        let earlier = start.addingTimeInterval(-60), restored = WorkoutTimerStore(directory: d, now: earlier)
        XCTAssertEqual(restored.issue, PracticeError.clockChanged.message)
        XCTAssertTrue(restored.hasSavedRecord(in: journal)); XCTAssertTrue(restored.mayFinish(in: journal), "The UI must allow cleanup after a proven save despite a clock error")
        _ = try restored.finish(in: journal, at: earlier)
        XCTAssertNil(restored.session); XCTAssertEqual(journal.entries.count, 1); XCTAssertEqual(journal.entries[0].value, 10)
    }
    func testRoutineSevenDaysAndStreakUsesYesterdayWhenTodayIsIncomplete() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
        func key(_ offset: Int) -> String { PracticeSummary.key(calendar.date(byAdding: .day, value: offset, to: now)!, calendar: calendar) }
        var checks: [String: [String: Bool]] = [:]
        for offset in -4 ... -1 { checks[key(offset)] = ["routine": true] }
        checks[key(-6)] = ["routine": true]
        var summary = PracticeSummary.routine("routine", checks: checks, now: now, calendar: calendar)
        XCTAssertEqual(summary.days.count, 7); XCTAssertEqual(summary.completedCount, 5); XCTAssertEqual(summary.streak, 4)
        checks[key(0)] = ["routine": true]
        summary = PracticeSummary.routine("routine", checks: checks, now: now, calendar: calendar)
        XCTAssertEqual(summary.completedCount, 6); XCTAssertEqual(summary.streak, 5)
        checks[key(-1)] = ["routine": false]; checks[key(0)] = ["routine": false]
        XCTAssertEqual(PracticeSummary.routine("routine", checks: checks, now: now, calendar: calendar).streak, 0)
    }
    func testCompletedWeeksExcludeTodayAndMissingDaysAndUseLastDailyValue() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
        func day(_ offset: Int, hour: Int = 12) -> Date { calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!)! }
        let entries = [Entry(date: day(-1), kind: "운동", value: 20), Entry(date: day(-1, hour: 18), kind: "운동", value: 10), Entry(date: day(-7), kind: "운동", value: 15), Entry(date: day(0), kind: "운동", value: 999), Entry(date: day(-8), kind: "운동", value: 60), Entry(date: day(-1), kind: "수면", value: 4), Entry(date: day(-1, hour: 18), kind: "수면", value: 8), Entry(date: day(-3), kind: "수면", value: 6), Entry(date: day(-7), kind: "마음", value: 2), Entry(date: day(-7, hour: 18), kind: "마음", value: 4)]
        let periods = PracticeSummary.completedWeeks(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(periods[0].exercise.value, 45); XCTAssertEqual(periods[0].exercise.recordedDays, 2)
        XCTAssertEqual(periods[1].exercise.value, 60); XCTAssertEqual(periods[1].exercise.recordedDays, 1)
        XCTAssertEqual(periods[0].sleep.value, 7); XCTAssertEqual(periods[0].sleep.recordedDays, 2)
        XCTAssertEqual(periods[0].mood.value, 4); XCTAssertEqual(periods[0].mood.recordedDays, 1)
        XCTAssertNil(periods[1].sleep.value); XCTAssertEqual(periods[1].sleep.recordedDays, 0)
        XCTAssertEqual(periods[0].end, calendar.startOfDay(for: now))
    }
    func testRoutineKeysRemainGregorianWithBuddhistCalendar() {
        var gregorian = Calendar(identifier: .gregorian); gregorian.timeZone = TimeZone(secondsFromGMT: 0)!
        var buddhist = Calendar(identifier: .buddhist); buddhist.timeZone = gregorian.timeZone
        let now = gregorian.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
        XCTAssertEqual(PracticeSummary.key(now, calendar: buddhist), "2026-10-12")
        let checks = ["2026-10-12": ["r": true], "2026-10-11": ["r": true], "2026-10-10": ["r": true]]
        let summary = PracticeSummary.routine("r", checks: checks, now: now, calendar: buddhist)
        XCTAssertEqual(summary.completedCount, 3); XCTAssertEqual(summary.streak, 3)
    }
    func testThirtyDayWindowsIncludeBoundariesAndExcludeToday() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        let entries = [Entry(date: day(-60), kind: "운동", value: 60), Entry(date: day(-30), kind: "운동", value: 30),
                       Entry(date: day(-1), kind: "운동", value: 10), Entry(date: day(0), kind: "운동", value: 999),
                       Entry(date: day(-61), kind: "운동", value: 888)]
        let periods = PracticeSummary.completedPeriods(entries: entries, window: .month, now: now, calendar: calendar)
        XCTAssertEqual(periods[0].exercise.value, 40); XCTAssertEqual(periods[1].exercise.value, 60)
        XCTAssertEqual(periods[0].start, day(-30)); XCTAssertEqual(periods[1].start, day(-60))
        XCTAssertEqual(periods[1].end, periods[0].start); XCTAssertEqual(periods[0].end, today)
        let days = PracticeSummary.daily(entries: entries, in: periods[0], calendar: calendar)
        XCTAssertEqual(days.count, 30); XCTAssertEqual(days.first?.exercise.value, 30)
        XCTAssertEqual(days.last?.exercise.value, 10)
        XCTAssertNil(days[1].exercise.value); XCTAssertEqual(days[1].exercise.recordedDays, 0)
    }
    func testDailySummaryUsesCalendarDaysAcrossDaylightSaving() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 12, hour: 12))!
        let period = PracticeSummary.completedPeriods(entries: [], window: .week, now: now, calendar: calendar)[0]
        let days = PracticeSummary.daily(entries: [], in: period, calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(Set(days.map(\.id)).count, 7)
        XCTAssertTrue(days.contains { $0.end.timeIntervalSince($0.start) == 23 * 3600 })
        XCTAssertEqual(days.last?.end, calendar.startOfDay(for: now))
    }
    func testDailyLastValueIsStableWhenTimestampsMatch() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
        let date = calendar.date(byAdding: .day, value: -1, to: now)!
        let entries = [Entry(id: "a", date: date, kind: "수면", value: 4), Entry(id: "z", date: date, kind: "수면", value: 8)]
        let first = PracticeSummary.completedWeeks(entries: entries, now: now, calendar: calendar)[0]
        let reversed = PracticeSummary.completedWeeks(entries: Array(entries.reversed()), now: now, calendar: calendar)[0]
        XCTAssertEqual(first.sleep.value, 8); XCTAssertEqual(reversed.sleep.value, 8)
        let days = PracticeSummary.daily(entries: entries, in: first, calendar: calendar)
        XCTAssertEqual(days.last?.sleep.value, 8); XCTAssertEqual(first.sleep.recordedDays, 1)
    }
    func testSharedSummaryKeepsMissingValuesAndOmitsPrivateNotes() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
        let date = calendar.date(byAdding: .day, value: -1, to: now)!
        let entries = [Entry(date: date, kind: "운동", value: 20, note: "PRIVATE-NOTE", source: "PRIVATE-SOURCE")]
        let periods = PracticeSummary.completedPeriods(entries: entries, window: .month, now: now, calendar: calendar)
        let text = PracticeSummary.shareText(recent: periods[0], prior: periods[1], window: .month, calendar: calendar)
        XCTAssertTrue(text.contains("30일 기록 요약")); XCTAssertTrue(text.contains("20분 (기록 1/30일)"))
        XCTAssertTrue(text.contains("기록 없음 (기록 0/30일)")); XCTAssertTrue(text.contains("2026.10.11"))
        XCTAssertFalse(text.contains("PRIVATE-NOTE")); XCTAssertFalse(text.contains("PRIVATE-SOURCE"))
    }

    func testSurveyRequiresEveryAnswerAndLimitsNotApplicableToMedication() { XCTAssertFalse(HealthSurveyResponse(answers: [-1, 2, 3, 5]).valid); XCTAssertFalse(HealthSurveyResponse(answers: [5, 2, 3, 5]).valid); XCTAssertTrue(HealthSurveyResponse(answers: [0, 2, 3, 5]).valid); XCTAssertFalse(HealthSurveyResponse(answers: [0, 2, 3]).valid) }
    func testBagTextPreservesLinesWithoutGuessingMedication() { XCTAssertEqual(MedicationBagText.lines("  원본 줄  \n\n아침 식후"), ["원본 줄", "아침 식후"]); XCTAssertEqual(MedicationBagText.lines(Array(repeating: "줄", count: 110).joined(separator: "\n")).count, 100); XCTAssertEqual(MedicationBagText.lines(String(repeating: "가", count: 600)).first?.count, 500) }
}

