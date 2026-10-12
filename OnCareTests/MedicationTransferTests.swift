import XCTest
@testable import OnCare

@MainActor private final class TransferCenter: MedicationNotifications {
    var authorizations = 0
    var plans: [MedicationPlan] = []
    func authorize() async throws -> Bool { authorizations += 1; return true }
    func allowed() async -> Bool { true }
    func apply(_ plans: [MedicationPlan]) async throws { self.plans = plans }
}
final class MedicationTransferTests: XCTestCase {
    func fixture() throws -> Data { try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: "MedicationInterop", withExtension: "json"))) }
    func testSharedAndroidIOSFixtureRoundTrip() throws {
        let state = try MedicationTransfer.decode(fixture())
        XCTAssertEqual(state.plans.first?.hour, 21); XCTAssertEqual(state.plans.first?.minute, 15)
        XCTAssertEqual(state.plans.first?.weekdays, Set(1...7)); XCTAssertEqual(state.checks["2026-10-12"]?.count, 1)
        let roundtrip = try MedicationTransfer.decode(MedicationTransfer.encode(state))
        XCTAssertEqual(roundtrip.plans, state.plans); XCTAssertEqual(roundtrip.checks, state.checks)
    }
    func testInvalidBackupDatesIdentifiersAndSizeAreRejected() throws {
        let fixture = try self.fixture()
        let source = try XCTUnwrap(String(data: fixture, encoding: .utf8))
        for invalid in [source.replacingOccurrences(of: "2026-10-12", with: "2026-02-30"), source.replacingOccurrences(of: "oncare-medications", with: "health-backup"), source.replacingOccurrences(of: "[1,2,3,4,5,6,7]", with: "[1,1,2]")] {
            XCTAssertThrowsError(try MedicationTransfer.decode(Data(invalid.utf8)))
        }
        XCTAssertThrowsError(try MedicationTransfer.decode(Data(repeating: 32, count: 65537)))
        var state = try MedicationTransfer.decode(fixture); state.checks["2026-10-12"] = ["unknown"]
        XCTAssertThrowsError(try MedicationTransfer.encode(state))
    }
    @MainActor func testRestoreDisablesNotificationsAndDoesNotAskPermission() async throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: d) }
        let center = TransferCenter(), store = MedicationStore(directory: d, notifications: TransferCenter())
        let old = MedicationPlan(name: "Old schedule", enabled: false); let saved = await store.save(old); XCTAssertTrue(saved)
        let restore = MedicationStore(directory: d, notifications: center)
        let imported = try MedicationTransfer.decode(fixture())
        let replaced = await restore.replaceFromBackup(imported); XCTAssertTrue(replaced)
        XCTAssertEqual(restore.state.plans.count, 1); XCTAssertFalse(restore.state.plans[0].enabled); XCTAssertEqual(center.authorizations, 0)
        XCTAssertTrue(center.plans.flatMap(\.notificationIDs).isEmpty)
        XCTAssertFalse(restore.state.plans.contains(where: { $0.id == old.id }))
    }
    @MainActor func testCorruptOriginalIsArchivedBeforeRestore() async throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: d) }
        let raw = Data("broken original".utf8); try raw.write(to: d.appendingPathComponent("medications-v1.json"))
        let store = MedicationStore(directory: d, notifications: TransferCenter()); XCTAssertFalse(store.readable)
        let imported = try MedicationTransfer.decode(fixture())
        let replaced = await store.replaceFromBackup(imported); XCTAssertTrue(replaced); XCTAssertTrue(store.readable)
        let archived = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil).first(where: { $0.lastPathComponent.hasPrefix("medications-preserved-") }))
        XCTAssertEqual(try Data(contentsOf: archived), raw)
        XCTAssertEqual(MedicationStore(directory: d, notifications: TransferCenter()).state.plans.count, 1)
    }
    func testHistoryIncludesEmptyDaysWithoutCallingThemMissed() throws {
        let state = try MedicationTransfer.decode(fixture())
        let formatter = ISO8601DateFormatter(); let now = try XCTUnwrap(formatter.date(from: "2026-10-12T12:00:00Z"))
        let history = MedicationInsights.history(state, now: now)
        XCTAssertEqual(history.count, 7); XCTAssertEqual(history[0].confirmed.count, 1); XCTAssertTrue(history[1].confirmed.isEmpty)
    }
}
