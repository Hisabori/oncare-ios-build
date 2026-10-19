import XCTest
import HealthKit
@testable import OnCare
final class AppleHealthTests: XCTestCase {
    private func record(_ id: String, type: String = "StepsRecord", source: String = "apple-health", date: Date) -> HealthRecord { HealthRecord(id: id, recordType: type, date: date, title: "기록", category: "활동", fields: ["count": .number(10)], source: source) }
    func testRefreshReplacesOnlyAppleTypeInsideWindow() throws {
        let now = Date(), start = now.addingTimeInterval(-86400)
        let old = record("hc:apple:old", date: now), android = record("hc:android", source: "health-connect:peer", date: now), outside = record("hc:apple:past", date: start.addingTimeInterval(-1)), weight = record("hc:apple:weight", type: "WeightRecord", date: now)
        let incoming = record("hc:apple:new", date: now)
        let result = try AppleHealthMerge.merge([old, android, outside, weight], incoming: [incoming], replace: ["StepsRecord"], start: start, now: now)
        XCTAssertEqual(Set(result.map(\.id)), [android.id, outside.id, weight.id, incoming.id])
    }
    func testEmptyAndPartialReadsPreservePreviousSamplesAndUpsert() throws {
        let now = Date(), start = now.addingTimeInterval(-86400), old = record("hc:apple:old", date: Date())
        let safeNow = now.addingTimeInterval(1)
        XCTAssertEqual(try AppleHealthMerge.merge([old], incoming: [], replace: [], start: start, now: safeNow).count, 1)
        XCTAssertThrowsError(try AppleHealthMerge.merge([old], incoming: [], replace: ["StepsRecord"], start: start, now: safeNow))
        XCTAssertEqual(try AppleHealthMerge.merge([old], incoming: [old], replace: [], start: start, now: safeNow).count, 1)
    }
    func testRejectsForeignOrFutureSamples() {
        let now = Date(), start = now.addingTimeInterval(-86400)
        XCTAssertThrowsError(try AppleHealthMerge.merge([], incoming: [record("hc:other", source: "health-connect:p", date: now)], replace: [], start: start, now: now))
        XCTAssertThrowsError(try AppleHealthMerge.merge([], incoming: [record("hc:apple:future", date: now.addingTimeInterval(1))], replace: [], start: start, now: now))
    }
    func testHealthKitQuantityPreservesUUIDUnitsAndSource() throws {
        let item = try XCTUnwrap(AppleHealthType.all.first { $0.id == "WeightRecord" }), now = Date()
        let sample = HKQuantitySample(type: try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .bodyMass)), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 65), start: now, end: now)
        let value = try item.encode(sample)
        XCTAssertEqual(value.id, "hc:apple:" + sample.uuid.uuidString); XCTAssertEqual(value.source, "apple-health"); XCTAssertEqual(value.summaryValue, "65 kg")
        try value.validate(now: now)
    }
    func testSleepStageComesFromOriginalSample() throws {
        let item = try XCTUnwrap(AppleHealthType.all.first { $0.id == "SleepSessionRecord" }), now = Date()
        let sample = HKCategorySample(type: try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)), value: HKCategoryValueSleepAnalysis.asleepREM.rawValue, start: now.addingTimeInterval(-600), end: now)
        XCTAssertEqual(try item.encode(sample).fields["stage"], .text("REM 수면"))
    }
    func testMindfulnessIsNotEncodedAsSleepStage() throws {
        let item = try XCTUnwrap(AppleHealthType.all.first { $0.id == "MindfulnessSessionRecord" }), now = Date()
        let sample = HKCategorySample(type: try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .mindfulSession)), value: 0, start: now.addingTimeInterval(-300), end: now)
        let record = try item.encode(sample)
        XCTAssertNil(record.fields["stage"]); XCTAssertEqual(record.fields["durationSeconds"], .number(300)); XCTAssertEqual(record.category, "마음")
    }
    func testStateOfMindKeepsOriginalValenceWithoutCreatingScore() throws {
        if #available(iOS 18.0, *) {
            let item = try XCTUnwrap(AppleHealthType.all.first { $0.id == "StateOfMindRecord" }), now = Date()
            let sample = HKStateOfMind(date: now, kind: .dailyMood, valence: -0.25, labels: [.calm], associations: [])
            let record = try item.encode(sample)
            XCTAssertEqual(record.fields["valence"], .number(-0.25)); XCTAssertEqual(record.fields["kind"], .text("하루의 기분")); XCTAssertNil(record.fields["score"])
            try record.validate(now: now)
        }
    }
}
