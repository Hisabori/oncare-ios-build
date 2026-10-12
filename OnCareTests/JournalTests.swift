import XCTest
@testable import OnCare

final class JournalTests: XCTestCase {
    func directory() throws -> URL { let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: d,withIntermediateDirectories: true); return d }
    @MainActor func testPersistenceAndLegacyMigration() throws {
        let d = try directory(); defer { try? FileManager.default.removeItem(at: d) }
        let legacy = [Entry(kind: "체중",value: 72.45)]
        let old = d.appendingPathComponent("journal.json")
        try JSONEncoder().encode(legacy).write(to: old)
        let journal = Journal(directory: d)
        XCTAssertEqual(journal.latest("체중")?.value,72.45)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path),"Keep the legacy original")
        XCTAssertTrue(journal.save(Entry(kind: "운동",value: 30,type: "걷기",sets: 3,reps: 12)))
        XCTAssertEqual(Journal(directory: d).entries.count,2)
        XCTAssertFalse(journal.save(Entry(kind: "체중",value: 0)))
        XCTAssertEqual(journal.entries.count,2)
    }
    @MainActor func testAndroidBackupRoundTripAndDuplicateMerge() throws {
        let d = try directory(); defer { try? FileManager.default.removeItem(at: d) }
        let timestamp = Int(Date().timeIntervalSince1970*1000)-1000
        let key = dateKey(Date())
        let raw = """
        {"version":3,"entries":[{"id":"android-lowercase-id","date":\(timestamp),"kind":"운동","value":30,"note":"산책","type":"걷기","sets":3,"reps":12}],"goals":{"weight":68,"exercise":150,"water":1800,"sleep":7.5},"routines":[{"id":"routine-id","title":"산책"}],"checks":{"\(key)":{"routine-id":true}}}
        """
        let backup = try CareBackup.decode(Data(raw.utf8))
        let journal = Journal(directory: d)
        XCTAssertTrue(journal.merge(backup)); XCTAssertTrue(journal.merge(backup))
        XCTAssertEqual(journal.entries.count,1)
        XCTAssertEqual(journal.goals.water,1800)
        XCTAssertTrue(journal.checked("routine-id"))
        let exported = try CareBackup.decode(journal.state.encoded())
        XCTAssertEqual(exported.entries.first?.id,"android-lowercase-id","Do not change imported ID case")
        XCTAssertEqual(exported.entries.first?.sets,3)
        XCTAssertEqual(Journal(directory: d).goals.weight,68)
        let v2 = try CareBackup.decode(Data("{\"version\":2,\"entries\":[]}".utf8))
        XCTAssertTrue(journal.merge(v2)); XCTAssertEqual(journal.goals.weight,68); XCTAssertEqual(journal.routines.count,1)
    }
    @MainActor func testDailyStatisticsAndRoutineHistory() throws {
        let d = try directory(); defer { try? FileManager.default.removeItem(at: d) }
        let journal = Journal(directory: d)
        let earlier = Date().addingTimeInterval(-60)
        XCTAssertTrue(journal.save(Entry(date: earlier,kind: "마음",value: 2)))
        XCTAssertTrue(journal.save(Entry(kind: "마음",value: 4)))
        XCTAssertEqual(journal.daily("마음",from: dayOffset(0)).count,1)
        XCTAssertEqual(journal.mean("마음",from: dayOffset(0),to: dayOffset(1)),4)
        XCTAssertTrue(journal.addRoutine("10분 걷기")); let id = journal.routines[0].id
        journal.toggle(id); XCTAssertTrue(Journal(directory: d).checked(id))
        journal.toggle(id); XCTAssertFalse(journal.checked(id))
        journal.deleteRoutine(id); XCTAssertEqual(journal.routines.count,0)
    }
    @MainActor func testInvalidBackupDoesNotMutateRecords() throws {
        let d = try directory(); defer { try? FileManager.default.removeItem(at: d) }
        let journal = Journal(directory: d); XCTAssertTrue(journal.save(Entry(kind: "체중",value: 70)))
        var invalid = journal.state; invalid.goals = CareGoals(weight: 0,exercise: 120,water: -1,sleep: 7)
        XCTAssertFalse(journal.merge(invalid)); XCTAssertEqual(journal.entries.count,1); XCTAssertEqual(journal.goals.water,1500)
        invalid = journal.state; invalid.routines = [Routine(id: "one",title: "걷기")]; invalid.checks = ["2026-99-99":["one":true]]
        XCTAssertThrowsError(try invalid.validate())
        invalid = journal.state; invalid.entries.append(invalid.entries[0]); XCTAssertThrowsError(try invalid.validate())
        invalid = journal.state; invalid.version = 99; XCTAssertThrowsError(try invalid.validate())
    }
    @MainActor func testIntelligenceContextExcludesPrivateTextAndOldRecords() throws {
        let d = try directory(); defer { try? FileManager.default.removeItem(at: d) }
        let journal = Journal(directory: d)
        XCTAssertTrue(journal.save(Entry(kind: "운동",value: 30,note: "PRIVATE_NOTE",type: "PRIVATE_TYPE")))
        XCTAssertTrue(journal.save(Entry(date: dayOffset(-10),kind: "운동",value: 100)))
        XCTAssertTrue(journal.addRoutine("PRIVATE_ROUTINE"))
        journal.toggle(journal.routines[0].id)
        let snapshot = IntelligenceContext.snapshot(journal)
        XCTAssertTrue(snapshot.contains("운동 합계: 30분"))
        XCTAssertTrue(snapshot.contains("루틴 완료 횟수: 1"))
        XCTAssertFalse(snapshot.contains("PRIVATE"))
        XCTAssertFalse(snapshot.contains("130분"))
    }
}
