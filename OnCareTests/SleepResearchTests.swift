import XCTest
@testable import OnCare

final class SleepResearchTests: XCTestCase {
    func testSilenceUsesFiniteFloorAndExactShape() throws {
        let features = try ResearchMel.extract([Float](repeating: 0, count: 120000))
        XCTAssertEqual(features.count, 64*2998)
        XCTAssertTrue(features.allSatisfy { $0.isFinite && abs($0 - Float(log(1e-10))) < 0.00001 })
    }
    func testInvalidEpochIsRejected() {
        XCTAssertThrowsError(try ResearchMel.extract([0]))
        var samples = [Float](repeating: 0, count: 120000); samples[10] = .nan
        XCTAssertThrowsError(try ResearchMel.extract(samples))
    }
    func testOldSessionAndResearchSummaryRoundTrip() throws {
        let old = SleepSoundSession(threshold: -35)
        let restored = try JSONDecoder().decode(SleepSoundSession.self, from: JSONEncoder().encode(old))
        XCTAssertNil(restored.research)
        let summary = SleepResearchSummary(analyzed: 3, candidates: 1, skipped: 2)
        XCTAssertEqual(try JSONDecoder().decode(SleepResearchSummary.self, from: JSONEncoder().encode(summary)).candidates, 1)
    }
}
